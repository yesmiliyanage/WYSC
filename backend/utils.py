"""Shared utilities used across multiple route modules."""

from datetime import datetime, timezone
from supabase import Client


def parse_datetime(value) -> datetime:
    """Parse an ISO-8601 datetime string into a timezone-aware datetime.

    Python < 3.11 cannot handle the 'Z' suffix in datetime.fromisoformat().
    Supabase timestamps are returned as either '…+00:00' or '…Z'.
    This helper normalises both forms so comparisons with
    datetime.now(timezone.utc) always work correctly.

    Also accepts an already-parsed datetime object and ensures it is
    timezone-aware (assumes UTC if naive).
    """
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    # Replace trailing 'Z' with an explicit UTC offset before parsing.
    s = value.replace("Z", "+00:00") if isinstance(value, str) and value.endswith("Z") else value
    return datetime.fromisoformat(s)


def upsert_preference(supabase: Client, user_id: str, category: str, item: str) -> None:
    """Increment order_count for an existing preference row, or insert a new one.

    Centralised here to avoid the duplicate implementations that previously
    existed in both routes/session.py and routes/challenge.py.
    """
    existing = (
        supabase.table("user_preferences")
        .select("preference_id, order_count")
        .eq("user_id", user_id)
        .eq("category", category)
        .eq("item", item)
        .execute()
    )
    if existing.data:
        pref = existing.data[0]
        supabase.table("user_preferences").update({
            "order_count": pref["order_count"] + 1,
            "last_ordered": datetime.now(timezone.utc).isoformat(),
        }).eq("preference_id", pref["preference_id"]).execute()
    else:
        supabase.table("user_preferences").insert({
            "user_id": user_id,
            "category": category,
            "item": item,
            "order_count": 1,
        }).execute()
