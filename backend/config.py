import os
from functools import lru_cache
from typing import Tuple

from dotenv import load_dotenv
from supabase import Client, create_client

load_dotenv()

# ── General ────────────────────────────────────────────────────────────────────
OPENAI_API_KEY      = os.getenv("OPENAI_API_KEY")
GOOGLE_PLACES_API_KEY = os.getenv("GOOGLE_PLACES_API_KEY")
PORT                = int(os.getenv("PORT", "5000"))
DEBUG               = os.getenv("FLASK_DEBUG", "false").lower() == "true"

# Comma-separated list of allowed CORS origins.
# Use "*" only for local development; set explicit origins in production.
# Example: CORS_ORIGINS=https://myapp.com,https://staging.myapp.com
_cors_raw    = os.getenv("CORS_ORIGINS", "*")
CORS_ORIGINS = [o.strip() for o in _cors_raw.split(",") if o.strip()]


# ── Supabase ───────────────────────────────────────────────────────────────────
def _load_supabase_credentials() -> Tuple[str, str]:
    """Return (url, key) from environment variables.

    Prefers SUPABASE_SERVICE_ROLE_KEY for server-side operations because the
    service role key bypasses Row Level Security, letting the backend act on
    behalf of any user without needing to forward the user JWT to the DB client.
    Falls back to SUPABASE_ANON_KEY so existing .env files keep working; in that
    case the application-level .eq("user_id", g.user_id) filters enforce access
    control instead.
    """
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY") or os.getenv("SUPABASE_ANON_KEY")
    if not url or not key:
        raise RuntimeError(
            "Supabase credentials are missing. "
            "Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (or SUPABASE_ANON_KEY) "
            "in your .env file."
        )
    return url, key


@lru_cache(maxsize=1)
def get_supabase_client() -> Client:
    """Create a Supabase client once and reuse it for the process lifetime."""
    url, key = _load_supabase_credentials()
    return create_client(url, key)
