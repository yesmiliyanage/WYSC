import secrets
from datetime import datetime, timedelta, timezone

from flask import Blueprint, g, jsonify, request

from config import get_supabase_client
from middleware.auth_middleware import require_auth
from models.enums import ChallengeStatus, InvitationStatus
from utils import parse_datetime

invite_bp = Blueprint("invite", __name__)

INVITE_EXPIRY_MINUTES = 5
CHALLENGE_EXPIRY_HOURS = 24


@invite_bp.route("/create", methods=["POST"])
@require_auth
def create_invite():
    """Create an invitation for a friend
    ---
    tags:
      - Invite
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
            - challenge_description
            - time_limit
          properties:
            session_id:
              type: string
            challenge_description:
              type: string
              example: "Take a 20-minute brisk walk"
            time_limit:
              type: integer
              example: 20
    responses:
      201:
        description: Invitation created
      400:
        description: Missing fields or invalid session
      404:
        description: Session not found
      500:
        description: Server error
    """
    body = request.get_json(silent=True) or {}
    session_id = body.get("session_id")
    challenge_desc = body.get("challenge_description")
    time_limit = body.get("time_limit")

    if not session_id or not challenge_desc or time_limit is None:
        return jsonify({"error": "session_id, challenge_description and time_limit are required."}), 400

    try:
        supabase = get_supabase_client()
        user_id = g.user_id

        # Verify session belongs to user and has session_type = invite_friend
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
        if session.get("session_type") != "invite_friend":
            return jsonify({"error": "Session type must be invite_friend."}), 400

        # Generate invite token
        invite_token = secrets.token_urlsafe(16)
        expiry_time = (datetime.now(timezone.utc) + timedelta(minutes=INVITE_EXPIRY_MINUTES)).isoformat()

        # Create invitation
        inv_resp = (
            supabase.table("invitations")
            .insert({
                "session_id": session_id,
                "inviter_user_id": user_id,
                "invite_token": invite_token,
                "status": InvitationStatus.PENDING.value,
                "challenge_description": challenge_desc,
                "challenge_time_limit": int(time_limit),
                "expiry_time": expiry_time,
            })
            .execute()
        )
        invitation = inv_resp.data[0]

        # Create challenge for the inviter
        challenge_expiry = (datetime.now(timezone.utc) + timedelta(hours=CHALLENGE_EXPIRY_HOURS)).isoformat()
        ch_resp = (
            supabase.table("challenges")
            .insert({
                "session_id": session_id,
                "challenge": challenge_desc,
                "time_limit": int(time_limit),
                "expiry_time": challenge_expiry,
                "status": ChallengeStatus.PENDING.value,
            })
            .execute()
        )
        challenge = ch_resp.data[0]

        return jsonify({
            "data": {
                "invitation_id": invitation["invitation_id"],
                "invite_token": invite_token,
                "invite_link": f"/invite/{invite_token}",
                "expiry_time": expiry_time,
                "challenge_id": challenge["challenge_id"],
            }
        }), 201

    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@invite_bp.route("/<token>", methods=["GET"])
def view_invite(token):
    """View an invitation (public, no auth required)
    ---
    tags:
      - Invite
    parameters:
      - name: token
        in: path
        type: string
        required: true
    responses:
      200:
        description: Invitation details
      404:
        description: Invitation not found or expired
      500:
        description: Server error
    """
    try:
        supabase = get_supabase_client()

        inv_resp = (
            supabase.table("invitations")
            .select("*, sessions(crave_item, calories)")
            .eq("invite_token", token)
            .execute()
        )
        if not inv_resp.data:
            return jsonify({"error": "Invitation not found."}), 404

        invitation = inv_resp.data[0]

        # Check expiry
        expiry = parse_datetime(invitation["expiry_time"])
        now = datetime.now(timezone.utc)
        if now > expiry:
            # Mark as expired if still pending
            if invitation["status"] == InvitationStatus.PENDING.value:
                supabase.table("invitations").update(
                    {"status": InvitationStatus.EXPIRED.value}
                ).eq("invitation_id", invitation["invitation_id"]).execute()
            return jsonify({"error": "Invitation has expired."}), 404

        expires_in = int((expiry - now).total_seconds())

        # Get inviter name
        profile_resp = (
            supabase.table("profiles")
            .select("name")
            .eq("user_id", invitation["inviter_user_id"])
            .execute()
        )
        inviter_name = profile_resp.data[0]["name"] if profile_resp.data else "Unknown"

        session_data = invitation.get("sessions", {})

        return jsonify({
            "data": {
                "inviter_name": inviter_name,
                "crave_item": session_data.get("crave_item"),
                "calories": session_data.get("calories"),
                "challenge": invitation["challenge_description"],
                "time_limit": invitation["challenge_time_limit"],
                "expires_in_seconds": expires_in,
                "status": invitation["status"],
            }
        }), 200

    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@invite_bp.route("/respond", methods=["POST"])
@require_auth
def respond_to_invite():
    """Accept or decline an invitation
    ---
    tags:
      - Invite
    security:
      - Bearer: []
    parameters:
      - name: body
        in: body
        required: true
        schema:
          type: object
          required:
            - invite_token
            - action
          properties:
            invite_token:
              type: string
            action:
              type: string
              enum: [accept, decline]
    responses:
      200:
        description: Invitation response processed
      400:
        description: Invalid action or invitation state
      404:
        description: Invitation not found
      500:
        description: Server error
    """
    body = request.get_json(silent=True) or {}
    invite_token = body.get("invite_token")
    action = body.get("action")

    if not invite_token or action not in ("accept", "decline"):
        return jsonify({"error": "invite_token and action (accept/decline) are required."}), 400

    try:
        supabase = get_supabase_client()
        user_id = g.user_id

        # Look up invitation
        inv_resp = (
            supabase.table("invitations")
            .select("*, sessions(crave_item, calories, session_type)")
            .eq("invite_token", invite_token)
            .execute()
        )
        if not inv_resp.data:
            return jsonify({"error": "Invitation not found."}), 404

        invitation = inv_resp.data[0]

        # Verify not expired
        expiry = parse_datetime(invitation["expiry_time"])
        if datetime.now(timezone.utc) > expiry:
            if invitation["status"] == InvitationStatus.PENDING.value:
                supabase.table("invitations").update(
                    {"status": InvitationStatus.EXPIRED.value}
                ).eq("invitation_id", invitation["invitation_id"]).execute()
            return jsonify({"error": "Invitation has expired."}), 400

        # Verify status is pending
        if invitation["status"] != InvitationStatus.PENDING.value:
            return jsonify({"error": f"Invitation is already {invitation['status']}."}), 400

        # Prevent self-invite
        if invitation["inviter_user_id"] == user_id:
            return jsonify({"error": "You cannot accept your own invitation."}), 400

        if action == "decline":
            supabase.table("invitations").update(
                {"status": InvitationStatus.DECLINED.value}
            ).eq("invitation_id", invitation["invitation_id"]).execute()
            return jsonify({"data": {"invitation_id": invitation["invitation_id"], "status": "declined"}}), 200

        # Accept flow
        session_data = invitation.get("sessions", {})

        # Create a session for the invitee (copy crave_item, calories, session_type)
        invitee_session_resp = (
            supabase.table("sessions")
            .insert({
                "user_id": user_id,
                "crave_item": session_data.get("crave_item", ""),
                "calories": session_data.get("calories"),
                "session_type": "invite_friend",
            })
            .execute()
        )
        invitee_session = invitee_session_resp.data[0]

        # Create a challenge for the invitee (same description/time_limit)
        challenge_expiry = (datetime.now(timezone.utc) + timedelta(hours=CHALLENGE_EXPIRY_HOURS)).isoformat()
        ch_resp = (
            supabase.table("challenges")
            .insert({
                "session_id": invitee_session["session_id"],
                "challenge": invitation["challenge_description"],
                "time_limit": invitation["challenge_time_limit"],
                "expiry_time": challenge_expiry,
                "status": ChallengeStatus.PENDING.value,
            })
            .execute()
        )
        challenge = ch_resp.data[0]

        # Update invitation
        supabase.table("invitations").update({
            "invitee_user_id": user_id,
            "invitee_session_id": invitee_session["session_id"],
            "status": InvitationStatus.ACCEPTED.value,
        }).eq("invitation_id", invitation["invitation_id"]).execute()

        return jsonify({
            "data": {
                "invitation_id": invitation["invitation_id"],
                "session_id": invitee_session["session_id"],
                "challenge_id": challenge["challenge_id"],
                "challenge": invitation["challenge_description"],
                "time_limit": invitation["challenge_time_limit"],
                "expiry_time": challenge_expiry,
            }
        }), 200

    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@invite_bp.route("/status/<invitation_id>", methods=["GET"])
@require_auth
def invite_status(invitation_id):
    """Check the status of an invitation (for inviter to poll)
    ---
    tags:
      - Invite
    security:
      - Bearer: []
    parameters:
      - name: invitation_id
        in: path
        type: string
        required: true
    responses:
      200:
        description: Invitation status
      404:
        description: Invitation not found
      500:
        description: Server error
    """
    try:
        supabase = get_supabase_client()

        inv_resp = (
            supabase.table("invitations")
            .select("*")
            .eq("invitation_id", invitation_id)
            .execute()
        )
        if not inv_resp.data:
            return jsonify({"error": "Invitation not found."}), 404

        invitation = inv_resp.data[0]

        # Verify the requester is the inviter or invitee
        if invitation["inviter_user_id"] != g.user_id and invitation.get("invitee_user_id") != g.user_id:
            return jsonify({"error": "Invitation not found."}), 404

        # Auto-expire if past expiry and still pending
        if invitation["status"] == InvitationStatus.PENDING.value:
            expiry = parse_datetime(invitation["expiry_time"])
            if datetime.now(timezone.utc) > expiry:
                supabase.table("invitations").update(
                    {"status": InvitationStatus.EXPIRED.value}
                ).eq("invitation_id", invitation_id).execute()
                invitation["status"] = InvitationStatus.EXPIRED.value

        result = {
            "invitation_id": invitation["invitation_id"],
            "status": invitation["status"],
        }

        # Include invitee name if accepted
        if invitation["status"] == InvitationStatus.ACCEPTED.value and invitation.get("invitee_user_id"):
            profile_resp = (
                supabase.table("profiles")
                .select("name")
                .eq("user_id", invitation["invitee_user_id"])
                .execute()
            )
            result["invitee_name"] = profile_resp.data[0]["name"] if profile_resp.data else "Unknown"

        return jsonify({"data": result}), 200

    except Exception as exc:
        return jsonify({"error": str(exc)}), 500
