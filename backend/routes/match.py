from datetime import datetime, timedelta, timezone

from flask import Blueprint, g, jsonify, request

from config import get_supabase_client
from middleware.auth_middleware import require_auth
from models.enums import ChallengeStatus, QueueStatus
from services import llm_service
from utils import parse_datetime

match_bp = Blueprint("match", __name__)

QUEUE_EXPIRY_MINUTES = 10
CHALLENGE_EXPIRY_HOURS = 24
CALORIE_MATCH_RANGE = 50


@match_bp.route("/queue", methods=["POST"])
@require_auth
def join_queue():
    """Join the matchmaking queue to challenge a random player
    ---
    tags:
      - Match
    security:
      - Bearer: []
    parameters:
      - name: body
        in: body
        required: true
        schema:
          type: object
          required:
            - session_id
          properties:
            session_id:
              type: string
    responses:
      200:
        description: Matched with an opponent or placed in queue
      400:
        description: Missing fields or already in queue
      404:
        description: Session not found
      500:
        description: Server error
    """
    body = request.get_json(silent=True) or {}
    session_id = body.get("session_id")

    if not session_id:
        return jsonify({"error": "session_id is required."}), 400

    try:
        supabase = get_supabase_client()
        user_id = g.user_id

        # Verify session belongs to user and has calories
        sess_resp = (
            supabase.table("sessions")
            .select("*")
            .eq("session_id", session_id)
            .eq("user_id", user_id)
            .execute()
        )
        if not sess_resp.data:
            return jsonify({"error": "Session not found."}), 404

        session = sess_resp.data[0]
        calories = session.get("calories")
        if not calories:
            return jsonify({"error": "Session must have calories set."}), 400

        # Check user not already in queue
        existing = (
            supabase.table("matchmaking_queue")
            .select("queue_id")
            .eq("user_id", user_id)
            .eq("status", QueueStatus.WAITING.value)
            .execute()
        )
        if existing.data:
            return jsonify({"error": "You are already in the matchmaking queue."}), 400

        # Attempt immediate match: find a waiting queue entry within calories ±50
        # and joined within the last QUEUE_EXPIRY_MINUTES (exclude stale/ghost entries)
        queue_cutoff = (datetime.now(timezone.utc) - timedelta(minutes=QUEUE_EXPIRY_MINUTES)).isoformat()
        queue_resp = (
            supabase.table("matchmaking_queue")
            .select("*")
            .eq("status", QueueStatus.WAITING.value)
            .neq("user_id", user_id)
            .gte("calories", calories - CALORIE_MATCH_RANGE)
            .lte("calories", calories + CALORIE_MATCH_RANGE)
            .gte("created_at", queue_cutoff)
            .limit(1)
            .execute()
        )

        if queue_resp.data:
            # Match found
            opponent_entry = queue_resp.data[0]
            avg_calories = (calories + opponent_entry["calories"]) // 2

            # Get user profiles for names
            profile_resp = (
                supabase.table("profiles")
                .select("user_id, name, age, weight")
                .in_("user_id", [user_id, opponent_entry["user_id"]])
                .execute()
            )
            profiles = {p["user_id"]: p for p in profile_resp.data} if profile_resp.data else {}
            my_profile = profiles.get(user_id, {})
            opponent_profile = profiles.get(opponent_entry["user_id"], {})

            # Generate challenge via LLM
            try:
                challenges = llm_service.generate_challenges(
                    calories=avg_calories,
                    user_age=my_profile.get("age"),
                    user_weight=my_profile.get("weight"),
                )
                challenge_data = challenges[0] if challenges else {
                    "description": f"Complete a workout to burn ~{avg_calories} kcal",
                    "time_limit": 30,
                }
            except Exception:
                challenge_data = {
                    "description": f"Complete a workout to burn ~{avg_calories} kcal",
                    "time_limit": 30,
                }

            challenge_desc = challenge_data["description"]
            time_limit = challenge_data["time_limit"]
            challenge_expiry = (datetime.now(timezone.utc) + timedelta(hours=CHALLENGE_EXPIRY_HOURS)).isoformat()

            # Create challenge for current user
            ch1_resp = (
                supabase.table("challenges")
                .insert({
                    "session_id": session_id,
                    "challenge": challenge_desc,
                    "time_limit": time_limit,
                    "expiry_time": challenge_expiry,
                    "status": ChallengeStatus.PENDING.value,
                })
                .execute()
            )
            challenge1 = ch1_resp.data[0]

            # Create challenge for opponent
            ch2_resp = (
                supabase.table("challenges")
                .insert({
                    "session_id": opponent_entry["session_id"],
                    "challenge": challenge_desc,
                    "time_limit": time_limit,
                    "expiry_time": challenge_expiry,
                    "status": ChallengeStatus.PENDING.value,
                })
                .execute()
            )
            challenge2 = ch2_resp.data[0]

            # Create match row
            match_resp = (
                supabase.table("matches")
                .insert({
                    "user1_id": opponent_entry["user_id"],
                    "user2_id": user_id,
                    "session_id_1": opponent_entry["session_id"],
                    "session_id_2": session_id,
                    "challenge_description": challenge_desc,
                    "challenge_time_limit": time_limit,
                    "status": "active",
                })
                .execute()
            )
            match = match_resp.data[0]

            # Update opponent queue entry to matched
            supabase.table("matchmaking_queue").update(
                {"status": QueueStatus.MATCHED.value}
            ).eq("queue_id", opponent_entry["queue_id"]).execute()

            # Insert current user's queue entry as matched
            supabase.table("matchmaking_queue").insert({
                "user_id": user_id,
                "session_id": session_id,
                "calories": calories,
                "status": QueueStatus.MATCHED.value,
            }).execute()

            return jsonify({
                "data": {
                    "matched": True,
                    "match_id": match["match_id"],
                    "opponent_name": opponent_profile.get("name", "Unknown"),
                    "challenge": challenge_desc,
                    "time_limit": time_limit,
                    "challenge_id": challenge1["challenge_id"],
                }
            }), 200

        # No match found — add to queue
        queue_insert = (
            supabase.table("matchmaking_queue")
            .insert({
                "user_id": user_id,
                "session_id": session_id,
                "calories": calories,
                "status": QueueStatus.WAITING.value,
            })
            .execute()
        )
        queue_entry = queue_insert.data[0]

        return jsonify({
            "data": {
                "matched": False,
                "queue_id": queue_entry["queue_id"],
                "message": "Waiting for opponent...",
            }
        }), 200

    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@match_bp.route("/status/<queue_id>", methods=["GET"])
@require_auth
def match_status(queue_id):
    """Check matchmaking queue status (polling endpoint)
    ---
    tags:
      - Match
    security:
      - Bearer: []
    parameters:
      - name: queue_id
        in: path
        type: string
        required: true
    responses:
      200:
        description: Queue/match status
      404:
        description: Queue entry not found
      500:
        description: Server error
    """
    try:
        supabase = get_supabase_client()
        user_id = g.user_id

        queue_resp = (
            supabase.table("matchmaking_queue")
            .select("*")
            .eq("queue_id", queue_id)
            .eq("user_id", user_id)
            .execute()
        )
        if not queue_resp.data:
            return jsonify({"error": "Queue entry not found."}), 404

        entry = queue_resp.data[0]

        # Auto-expire if waiting too long
        if entry["status"] == QueueStatus.WAITING.value:
            created = parse_datetime(entry["created_at"])
            if datetime.now(timezone.utc) > created + timedelta(minutes=QUEUE_EXPIRY_MINUTES):
                supabase.table("matchmaking_queue").update(
                    {"status": QueueStatus.EXPIRED.value}
                ).eq("queue_id", queue_id).execute()
                return jsonify({"data": {"status": "expired"}}), 200

        if entry["status"] == QueueStatus.MATCHED.value:
            # Find the match
            match_resp = (
                supabase.table("matches")
                .select("*")
                .or_(
                    f"session_id_1.eq.{entry['session_id']},session_id_2.eq.{entry['session_id']}"
                )
                .execute()
            )
            if match_resp.data:
                match = match_resp.data[0]
                opponent_id = match["user2_id"] if match["user1_id"] == user_id else match["user1_id"]

                profile_resp = (
                    supabase.table("profiles")
                    .select("name")
                    .eq("user_id", opponent_id)
                    .execute()
                )
                opponent_name = profile_resp.data[0]["name"] if profile_resp.data else "Unknown"

                # Get the user's challenge
                ch_resp = (
                    supabase.table("challenges")
                    .select("challenge_id")
                    .eq("session_id", entry["session_id"])
                    .execute()
                )
                challenge_id = ch_resp.data[0]["challenge_id"] if ch_resp.data else None

                return jsonify({
                    "data": {
                        "status": "matched",
                        "match_id": match["match_id"],
                        "opponent_name": opponent_name,
                        "challenge": match["challenge_description"],
                        "time_limit": match["challenge_time_limit"],
                        "challenge_id": challenge_id,
                    }
                }), 200

        return jsonify({"data": {"status": entry["status"]}}), 200

    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@match_bp.route("/cancel", methods=["POST"])
@require_auth
def cancel_queue():
    """Cancel a matchmaking queue entry
    ---
    tags:
      - Match
    security:
      - Bearer: []
    parameters:
      - name: body
        in: body
        required: true
        schema:
          type: object
          required:
            - queue_id
          properties:
            queue_id:
              type: string
    responses:
      200:
        description: Queue entry cancelled
      400:
        description: Cannot cancel
      404:
        description: Queue entry not found
      500:
        description: Server error
    """
    body = request.get_json(silent=True) or {}
    queue_id = body.get("queue_id")

    if not queue_id:
        return jsonify({"error": "queue_id is required."}), 400

    try:
        supabase = get_supabase_client()

        queue_resp = (
            supabase.table("matchmaking_queue")
            .select("*")
            .eq("queue_id", queue_id)
            .eq("user_id", g.user_id)
            .execute()
        )
        if not queue_resp.data:
            return jsonify({"error": "Queue entry not found."}), 404

        entry = queue_resp.data[0]
        if entry["status"] != QueueStatus.WAITING.value:
            return jsonify({"error": f"Cannot cancel queue entry with status: {entry['status']}."}), 400

        supabase.table("matchmaking_queue").update(
            {"status": QueueStatus.CANCELLED.value}
        ).eq("queue_id", queue_id).execute()

        return jsonify({"data": {"queue_id": queue_id, "status": "cancelled"}}), 200

    except Exception as exc:
        return jsonify({"error": str(exc)}), 500
