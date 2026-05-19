from flask import Flask, jsonify
from flask_cors import CORS
from flasgger import Swagger

from config import CORS_ORIGINS, DEBUG, PORT
from routes.auth import auth_bp
from routes.session import session_bp
from routes.challenge import challenge_bp
from routes.user import user_bp
from routes.invite import invite_bp
from routes.match import match_bp

app = Flask(__name__)

# ── CORS ───────────────────────────────────────────────────────────────────────
# Set CORS_ORIGINS in .env to restrict origins in production.
# Example: CORS_ORIGINS=https://yourapp.com
# Default "*" is only suitable for local development.
CORS(app, origins=CORS_ORIGINS)

# ── Swagger ────────────────────────────────────────────────────────────────────
swagger_config = {
    "headers": [],
    "specs": [
        {
            "endpoint": "apispec",
            "route": "/apispec.json",
            "rule_filter": lambda rule: True,
            "model_filter": lambda tag: True,
        }
    ],
    "static_url_path": "/flasgger_static",
    "swagger_ui": True,
    "specs_route": "/apidocs/",
}

swagger_template = {
    "info": {
        "title": "CraveBalance API",
        "description": "Backend API for CraveBalance — manage cravings, auth, and data.",
        "version": "1.0.0",
    },
    "securityDefinitions": {
        "Bearer": {
            "type": "apiKey",
            "name": "Authorization",
            "in": "header",
            "description": "Paste your token with the Bearer prefix. Example: Bearer eyJhbGciOi...",
        }
    },
}

Swagger(app, config=swagger_config, template=swagger_template)

# ── Blueprints ─────────────────────────────────────────────────────────────────
app.register_blueprint(auth_bp,      url_prefix="/auth")
app.register_blueprint(session_bp,   url_prefix="/session")
app.register_blueprint(challenge_bp, url_prefix="/challenge")
app.register_blueprint(user_bp,      url_prefix="/user")
app.register_blueprint(invite_bp,    url_prefix="/invite")
app.register_blueprint(match_bp,     url_prefix="/match")


# ── General routes ─────────────────────────────────────────────────────────────
@app.route("/", methods=["GET"])
def home():
    """API welcome endpoint
    ---
    tags:
      - General
    responses:
      200:
        description: API is running
    """
    return jsonify({"message": "CraveBalance API is running."})


@app.route("/health", methods=["GET"])
def health():
    """Health check
    ---
    tags:
      - General
    responses:
      200:
        description: API is healthy
    """
    return jsonify({"status": "OK"}), 200


@app.route("/supabase/health", methods=["GET"])
def supabase_health():
    """Supabase connection check
    ---
    tags:
      - General
    responses:
      200:
        description: Supabase client is connected
      500:
        description: Supabase connection failed
    """
    try:
        from config import get_supabase_client
        get_supabase_client()
        return jsonify({"status": "connected"}), 200
    except Exception as exc:
        return jsonify({"status": "error", "details": str(exc)}), 500


# ── Global error handlers ──────────────────────────────────────────────────────
@app.errorhandler(404)
def not_found(_e):
    return jsonify({"error": "Endpoint not found."}), 404


@app.errorhandler(405)
def method_not_allowed(_e):
    return jsonify({"error": "Method not allowed."}), 405


@app.errorhandler(500)
def internal_error(_e):
    return jsonify({"error": "An unexpected server error occurred."}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT, debug=DEBUG)
