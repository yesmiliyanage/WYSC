"""WSGI entry point used by gunicorn in production.

Start locally:
    python app.py

Deploy with gunicorn (Railway / Render / Heroku):
    gunicorn wsgi:app

With explicit worker count and port binding:
    gunicorn --workers 2 --bind 0.0.0.0:$PORT wsgi:app
"""
from app import app  # noqa: F401 — re-exported for gunicorn
