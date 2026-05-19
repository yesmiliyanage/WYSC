import math

from flask import Blueprint, g, jsonify, request

from config import get_supabase_client
from middleware.auth_middleware import require_auth
from models.enums import SessionType
from services import llm_service, places_service
from utils import upsert_preference

session_bp = Blueprint("session", __name__)

MATURITY_THRESHOLD = 5  # preferences count to trigger personalisation
SKIP_BONUS_POINTS = 50
MAX_REGENERATIONS = 3


@session_bp.route("/crave", methods=["POST"])
@require_auth
def submit_crave():
    """Submit a craving and get specific options
    ---
    tags:
      - Session
    security:
      - Bearer: []
    parameters:
      - name: body
        in: body
        required: true
        schema:
          type: object
          required:
            - crave_item
            - latitude
            - longitude
          properties:
            crave_item:
              type: string
              example: crepe
            latitude:
              type: number
              example: 6.9271
            longitude:
              type: number
              example: 79.8612
    responses:
      200:
        description: Craving options generated
      400:
        description: Missing required fields
      500:
        description: Server error
    """
    body = request.get_json(silent=True) or {}
    crave_item = body.get("crave_item")
    lat = body.get("latitude")
    lng = body.get("longitude")

    if not crave_item or lat is None or lng is None:
        return jsonify({"error": "crave_item, latitude and longitude are required."}), 400

    try:
        supabase = get_supabase_client()
        user_id = g.user_id

        # Check user preferences for this category
        prefs_resp = (
            supabase.table("user_preferences")
            .select("*")
            .eq("user_id", user_id)
            .eq("category", crave_item.lower())
            .execute()
        )
        preferences = prefs_resp.data or []
        is_personalized = len(preferences) >= MATURITY_THRESHOLD

        # Find nearby places
        places = places_service.search_nearby_places(crave_item, lat, lng)

        # Generate specific options via LLM
        try:
            options = llm_service.generate_craving_options(
                crave_item,
                places,
                user_preferences=preferences if is_personalized else None,
            )
        except Exception as llm_err:
            return jsonify({"error": f"LLM service error: {llm_err}"}), 502

        # Create session record
        session_resp = (
            supabase.table("sessions")
            .insert({
                "user_id": user_id,
                "crave_item": crave_item,
                "location_options": {"places": places, "options": options},
            })
            .execute()
        )
        session = session_resp.data[0]

        return jsonify({
            "data": {
                "session_id": session["session_id"],
                "options": options,
                "personalized": is_personalized,
            }
        }), 200

    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@session_bp.route("/select", methods=["POST"])
@require_auth
def select_option():
    """Select a craving option and get calorie estimate
    ---
    tags:
      - Session
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
            - selected_option
          properties:
            session_id:
              type: string
            selected_option:
              type: string
              example: Chocolate crepe from La Creperie
    responses:
      200:
        description: Option selected, calories estimated
      400:
        description: Missing fields
      404:
        description: Session not found
      500:
        description: Server error
    """
    body = request.get_json(silent=True) or {}
    session_id = body.get("session_id")
    selected_option = body.get("selected_option")

    if not session_id or not selected_option:
        return jsonify({"error": "session_id and selected_option are required."}), 400

    try:
        supabase = get_supabase_client()

        # Verify session belongs to user
        sess_resp = (
            supabase.table("sessions")
            .select("*")
            .eq("session_id", session_id)
            .eq("user_id", g.user_id)
            .execute()
        )
        if not sess_resp.data:
            return jsonify({"error": "Session not found."}), 404

        # Estimate calories via LLM
        try:
            calories = llm_service.estimate_calories(selected_option)
        except Exception as llm_err:
            return jsonify({"error": f"LLM service error: {llm_err}"}), 502

        # Update session
        supabase.table("sessions").update({
            "crave_item": selected_option,
            "calories": calories,
        }).eq("session_id", session_id).execute()

        return jsonify({
            "data": {
                "session_id": session_id,
                "selected_item": selected_option,
                "estimated_calories": calories,
                "session_types": [t.value for t in SessionType],
            }
        }), 200

    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@session_bp.route("/choose-type", methods=["POST"])
@require_auth
def choose_session_type():
    """Choose a session type (solo challenge, invite friend, etc.)
    ---
    tags:
      - Session
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
            - session_type
          properties:
            session_id:
              type: string
            session_type:
              type: string
              enum: [solo_challenge, invite_friend, challenge_random, healthy_route, skip]
    responses:
      200:
        description: Session type set. Returns challenges for solo_challenge.
      400:
        description: Invalid input
      404:
        description: Session not found
      500:
        description: Server error
    """
    body = request.get_json(silent=True) or {}
    session_id = body.get("session_id")
    session_type = body.get("session_type")

    if not session_id or not session_type:
        return jsonify({"error": "session_id and session_type are required."}), 400

    # Validate enum
    try:
        stype = SessionType(session_type)
    except ValueError:
        valid = [t.value for t in SessionType]
        return jsonify({"error": f"Invalid session_type. Must be one of: {valid}"}), 400

    try:
        supabase = get_supabase_client()

        # Verify session + get calories
        sess_resp = (
            supabase.table("sessions")
            .select("*")
            .eq("session_id", session_id)
            .eq("user_id", g.user_id)
            .execute()
        )
        if not sess_resp.data:
            return jsonify({"error": "Session not found."}), 404

        session = sess_resp.data[0]

        # Update session type
        supabase.table("sessions").update({
            "session_type": stype.value,
        }).eq("session_id", session_id).execute()

        if stype == SessionType.SOLO_CHALLENGE:
            # Fetch user profile for personalised challenges
            profile_resp = (
                supabase.table("profiles")
                .select("age, weight")
                .eq("user_id", g.user_id)
                .execute()
            )
            profile = profile_resp.data[0] if profile_resp.data else {}

            try:
                challenges = llm_service.generate_challenges(
                    calories=session.get("calories", 300),
                    user_age=profile.get("age"),
                    user_weight=profile.get("weight"),
                )
            except Exception as llm_err:
                return jsonify({"error": f"LLM service error: {llm_err}"}), 502

            return jsonify({
                "data": {
                    "session_id": session_id,
                    "session_type": stype.value,
                    "challenges": challenges,
                }
            }), 200

        if stype == SessionType.SKIP:
            # Award willpower bonus
            profile_resp = (
                supabase.table("profiles")
                .select("total_points")
                .eq("user_id", g.user_id)
                .execute()
            )
            current_points = profile_resp.data[0]["total_points"] if profile_resp.data else 0
            new_total = current_points + SKIP_BONUS_POINTS

            supabase.table("profiles").update(
                {"total_points": new_total}
            ).eq("user_id", g.user_id).execute()

            # Look up rank
            rank_resp = (
                supabase.table("ranks")
                .select("rank_type")
                .lte("min_points", new_total)
                .gte("max_points", new_total)
                .execute()
            )
            rank = rank_resp.data[0]["rank_type"] if rank_resp.data else "Beginner"

            return jsonify({
                "data": {
                    "session_id": session_id,
                    "session_type": stype.value,
                    "message": "Willpower! You resisted the craving.",
                    "points_earned": SKIP_BONUS_POINTS,
                    "total_points": new_total,
                    "rank": rank,
                }
            }), 200

        if stype == SessionType.INVITE_FRIEND:
            # Generate challenges for the inviter to pick from before creating invite
            profile_resp = (
                supabase.table("profiles")
                .select("age, weight")
                .eq("user_id", g.user_id)
                .execute()
            )
            profile = profile_resp.data[0] if profile_resp.data else {}

            try:
                challenges = llm_service.generate_challenges(
                    calories=session.get("calories", 300),
                    user_age=profile.get("age"),
                    user_weight=profile.get("weight"),
                )
            except Exception as llm_err:
                return jsonify({"error": f"LLM service error: {llm_err}"}), 502

            return jsonify({
                "data": {
                    "session_id": session_id,
                    "session_type": stype.value,
                    "challenges": challenges,
                    "message": "Select a challenge, then create an invite via POST /invite/create.",
                }
            }), 200

        if stype == SessionType.HEALTHY_ROUTE:
            # Generate healthy substitute suggestions
            try:
                suggestions = llm_service.generate_healthy_substitute(
                    crave_item=session.get("crave_item", ""),
                    calories=session.get("calories", 300),
                )
            except Exception as llm_err:
                return jsonify({"error": f"LLM service error: {llm_err}"}), 502

            # Store suggestions in session for regeneration tracking
            loc_opts = session.get("location_options") or {}
            loc_opts["healthy_suggestions"] = suggestions
            loc_opts["healthy_regenerations"] = 0
            loc_opts["healthy_excluded"] = []
            supabase.table("sessions").update(
                {"location_options": loc_opts}
            ).eq("session_id", session_id).execute()

            return jsonify({
                "data": {
                    "session_id": session_id,
                    "session_type": stype.value,
                    "suggestions": suggestions,
                    "regenerations_remaining": MAX_REGENERATIONS,
                    "message": "Pick a healthy substitute, or call POST /session/healthy/regenerate for different options. Accept via POST /session/healthy/accept.",
                }
            }), 200

        if stype == SessionType.CHALLENGE_RANDOM:
            return jsonify({
                "data": {
                    "session_id": session_id,
                    "session_type": stype.value,
                    "message": "Session type set. Join the matchmaking queue via POST /match/queue.",
                }
            }), 200

        return jsonify({
            "data": {
                "session_id": session_id,
                "session_type": stype.value,
            }
        }), 200

    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


# ------------------------------------------------------------------
# Regenerate endpoints (max 3 retries each)
# ------------------------------------------------------------------

@session_bp.route("/crave/regenerate", methods=["POST"])
@require_auth
def regenerate_crave_options():
    """Regenerate craving options (different suggestions)
    ---
    tags:
      - Session
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
        description: New craving options generated
      400:
        description: Regeneration limit reached or missing fields
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

        sess_resp = (
            supabase.table("sessions")
            .select("*")
            .eq("session_id", session_id)
            .eq("user_id", g.user_id)
            .execute()
        )
        if not sess_resp.data:
            return jsonify({"error": "Session not found."}), 404

        session = sess_resp.data[0]
        loc_opts = session.get("location_options") or {}

        regen_count = loc_opts.get("crave_regenerations", 0)
        if regen_count >= MAX_REGENERATIONS:
            return jsonify({"error": f"Maximum {MAX_REGENERATIONS} regenerations reached. Please pick from the current options."}), 400

        places = loc_opts.get("places", [])

        # Check user preferences
        crave_item = session.get("crave_item", "")
        prefs_resp = (
            supabase.table("user_preferences")
            .select("*")
            .eq("user_id", g.user_id)
            .eq("category", crave_item.lower())
            .execute()
        )
        preferences = prefs_resp.data or []
        is_personalized = len(preferences) >= MATURITY_THRESHOLD

        try:
            options = llm_service.generate_craving_options(
                crave_item,
                places,
                user_preferences=preferences if is_personalized else None,
            )
        except Exception as llm_err:
            return jsonify({"error": f"LLM service error: {llm_err}"}), 502

        # Update session with new options and increment count
        loc_opts["options"] = options
        loc_opts["crave_regenerations"] = regen_count + 1
        supabase.table("sessions").update(
            {"location_options": loc_opts}
        ).eq("session_id", session_id).execute()

        return jsonify({
            "data": {
                "session_id": session_id,
                "options": options,
                "personalized": is_personalized,
                "regenerations_remaining": MAX_REGENERATIONS - (regen_count + 1),
            }
        }), 200

    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@session_bp.route("/challenges/regenerate", methods=["POST"])
@require_auth
def regenerate_challenges():
    """Regenerate challenge suggestions (different challenges)
    ---
    tags:
      - Session
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
        description: New challenges generated
      400:
        description: Regeneration limit reached or invalid session type
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

        sess_resp = (
            supabase.table("sessions")
            .select("*")
            .eq("session_id", session_id)
            .eq("user_id", g.user_id)
            .execute()
        )
        if not sess_resp.data:
            return jsonify({"error": "Session not found."}), 404

        session = sess_resp.data[0]

        if session.get("session_type") not in ("solo_challenge", "invite_friend"):
            return jsonify({"error": "Challenge regeneration is only for solo_challenge and invite_friend sessions."}), 400

        loc_opts = session.get("location_options") or {}
        regen_count = loc_opts.get("challenge_regenerations", 0)
        if regen_count >= MAX_REGENERATIONS:
            return jsonify({"error": f"Maximum {MAX_REGENERATIONS} regenerations reached. Please pick from the current challenges."}), 400

        profile_resp = (
            supabase.table("profiles")
            .select("age, weight")
            .eq("user_id", g.user_id)
            .execute()
        )
        profile = profile_resp.data[0] if profile_resp.data else {}

        try:
            challenges = llm_service.generate_challenges(
                calories=session.get("calories", 300),
                user_age=profile.get("age"),
                user_weight=profile.get("weight"),
            )
        except Exception as llm_err:
            return jsonify({"error": f"LLM service error: {llm_err}"}), 502

        loc_opts["challenge_regenerations"] = regen_count + 1
        supabase.table("sessions").update(
            {"location_options": loc_opts}
        ).eq("session_id", session_id).execute()

        return jsonify({
            "data": {
                "session_id": session_id,
                "challenges": challenges,
                "regenerations_remaining": MAX_REGENERATIONS - (regen_count + 1),
            }
        }), 200

    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


# ------------------------------------------------------------------
# Healthy route endpoints
# ------------------------------------------------------------------

@session_bp.route("/healthy/regenerate", methods=["POST"])
@require_auth
def regenerate_healthy():
    """Regenerate healthy substitute suggestions
    ---
    tags:
      - Session
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
        description: New healthy suggestions generated
      400:
        description: Regeneration limit reached or wrong session type
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

        sess_resp = (
            supabase.table("sessions")
            .select("*")
            .eq("session_id", session_id)
            .eq("user_id", g.user_id)
            .execute()
        )
        if not sess_resp.data:
            return jsonify({"error": "Session not found."}), 404

        session = sess_resp.data[0]

        if session.get("session_type") != "healthy_route":
            return jsonify({"error": "This endpoint is only for healthy_route sessions."}), 400

        loc_opts = session.get("location_options") or {}
        regen_count = loc_opts.get("healthy_regenerations", 0)
        if regen_count >= MAX_REGENERATIONS:
            return jsonify({"error": f"Maximum {MAX_REGENERATIONS} regenerations reached. Please pick from the current suggestions."}), 400

        # Collect previously shown suggestions to exclude
        excluded = loc_opts.get("healthy_excluded", [])
        current_suggestions = loc_opts.get("healthy_suggestions", [])
        for s in current_suggestions:
            name = s.get("suggestion", "")
            if name and name not in excluded:
                excluded.append(name)

        try:
            suggestions = llm_service.generate_healthy_substitute(
                crave_item=session.get("crave_item", ""),
                calories=session.get("calories", 300),
                exclude_items=excluded if excluded else None,
            )
        except Exception as llm_err:
            return jsonify({"error": f"LLM service error: {llm_err}"}), 502

        loc_opts["healthy_suggestions"] = suggestions
        loc_opts["healthy_regenerations"] = regen_count + 1
        loc_opts["healthy_excluded"] = excluded
        supabase.table("sessions").update(
            {"location_options": loc_opts}
        ).eq("session_id", session_id).execute()

        return jsonify({
            "data": {
                "session_id": session_id,
                "suggestions": suggestions,
                "regenerations_remaining": MAX_REGENERATIONS - (regen_count + 1),
            }
        }), 200

    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@session_bp.route("/healthy/accept", methods=["POST"])
@require_auth
def accept_healthy():
    """Accept a healthy substitute — awards points and logs the choice
    ---
    tags:
      - Session
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
            - selected_suggestion
          properties:
            session_id:
              type: string
            selected_suggestion:
              type: string
              example: "Greek yogurt with honey and berries"
    responses:
      200:
        description: Healthy choice accepted, points awarded
      400:
        description: Missing fields or wrong session type
      404:
        description: Session not found
      500:
        description: Server error
    """
    body = request.get_json(silent=True) or {}
    session_id = body.get("session_id")
    selected = body.get("selected_suggestion")

    if not session_id or not selected:
        return jsonify({"error": "session_id and selected_suggestion are required."}), 400

    try:
        supabase = get_supabase_client()

        sess_resp = (
            supabase.table("sessions")
            .select("*")
            .eq("session_id", session_id)
            .eq("user_id", g.user_id)
            .execute()
        )
        if not sess_resp.data:
            return jsonify({"error": "Session not found."}), 404

        session = sess_resp.data[0]

        if session.get("session_type") != "healthy_route":
            return jsonify({"error": "This endpoint is only for healthy_route sessions."}), 400

        calories = session.get("calories") or 300
        points = math.floor(calories / 10)

        # Update session with the healthy choice and a positive rating
        supabase.table("sessions").update({
            "crave_item": selected,
            "rating": 7,
        }).eq("session_id", session_id).execute()

        # Update user total points
        profile_resp = (
            supabase.table("profiles")
            .select("total_points")
            .eq("user_id", g.user_id)
            .execute()
        )
        current_points = profile_resp.data[0]["total_points"] if profile_resp.data else 0
        new_total = current_points + points

        supabase.table("profiles").update(
            {"total_points": new_total}
        ).eq("user_id", g.user_id).execute()

        # Log preference
        original_crave = session.get("crave_item", "")
        category = original_crave.split(" ")[-1].lower() if original_crave else "healthy"
        upsert_preference(supabase, g.user_id, category, selected)

        # Look up rank
        rank_resp = (
            supabase.table("ranks")
            .select("rank_type")
            .lte("min_points", new_total)
            .gte("max_points", new_total)
            .execute()
        )
        rank = rank_resp.data[0]["rank_type"] if rank_resp.data else "Beginner"

        return jsonify({
            "data": {
                "session_id": session_id,
                "selected_suggestion": selected,
                "points_earned": points,
                "total_points": new_total,
                "rank": rank,
                "message": "Great choice! You picked a healthier option.",
            }
        }), 200

    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


