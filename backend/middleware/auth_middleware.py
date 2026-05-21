from functools import wraps

from flask import g, jsonify, request

from config import get_supabase_client

# In-memory cache of user IDs whose profiles have already been created this
# process lifetime.  Avoids a DB round-trip on every single request.
_known_users: set = set()


def require_auth(f):
    """Decorator that reads the X-User-ID header and sets g.user_id.

    Authentication is handled client-side: the Flutter app generates a
    persistent UUID on first launch and sends it with every request.
    No token verification is performed.

    On the very first request from a new user ID, a default profile row
    is upserted so all downstream queries have a profile to work with.
    """

    @wraps(f)
    def decorated(*args, **kwargs):
        user_id = request.headers.get("X-User-ID", "").strip()
        if not user_id:
            return jsonify({"error": "Missing X-User-ID header."}), 401

        g.user_id = user_id

        # Auto-create profile once per user_id per process run
        if user_id not in _known_users:
            try:
                supabase = get_supabase_client()
                supabase.table("profiles").upsert(
                    {"user_id": user_id, "name": "User", "total_points": 0},
                    on_conflict="user_id",
                    ignore_duplicates=True,
                ).execute()
            except Exception:
                pass  # Never block a request over profile creation
            finally:
                _known_users.add(user_id)

        return f(*args, **kwargs)

    return decorated
