# backend/app/main.py
from __future__ import annotations

import os
from datetime import datetime, timezone
from flask import Flask

from app.admin import admin_bp
from app.api.routes import api_bp
from app.ai.routes import ai_bp
from app.settings import SECRET_KEY

try:
    from google.cloud.firestore_v1 import _helpers as fs_helpers  # for Timestamp detection
except Exception:
    fs_helpers = None


def create_app() -> Flask:
    app = Flask(__name__)

    # Secret key for session/flash
    app.config["SECRET_KEY"] = SECRET_KEY or os.environ.get("SECRET_KEY") or "dev-secret"

    # Register blueprints
    app.register_blueprint(admin_bp)
    app.register_blueprint(api_bp, url_prefix="/api")
    app.register_blueprint(ai_bp, url_prefix="/ai")

    # Jinja: human-readable timestamp filter
    @app.template_filter("humants")
    def _human_ts(value):
        """
        Convert Firestore Timestamp / Python datetime / epoch seconds to a human-readable UTC string.
        Usage in templates: {{ quiz.updated_at|humants }}
        """
        try:
            if value is None:
                return "—"

            # Firestore Timestamp?
            if fs_helpers and getattr(value, "__class__", None).__name__ == "Timestamp":
                dt = value.to_datetime().astimezone(timezone.utc)
                return dt.strftime("%Y-%m-%d %H:%M:%S UTC")

            # Python datetime?
            if hasattr(value, "isoformat"):
                # assume datetime
                dt = value
                if getattr(dt, "tzinfo", None) is None:
                    dt = dt.replace(tzinfo=timezone.utc)
                else:
                    dt = dt.astimezone(timezone.utc)
                return dt.strftime("%Y-%m-%d %H:%M:%S UTC")

            # Fallback: assume epoch numeric
            ts = int(value)
            dt = datetime.fromtimestamp(ts, tz=timezone.utc)
            return dt.strftime("%Y-%m-%d %H:%M:%S UTC")
        except Exception:
            return str(value)

    # Jinja: a 'now()' helper (used in footer for year)
    @app.context_processor
    def inject_now():
        return {"now": datetime.utcnow}

    @app.route("/")
    def root():
        # Simple convenience redirect during development
        from flask import redirect, url_for
        return redirect(url_for("admin.dashboard"))

    return app


# For 'flask run' with FLASK_APP=app.main
app = create_app()
