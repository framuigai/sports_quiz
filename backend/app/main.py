from __future__ import annotations

import os
from datetime import datetime
from flask import Flask

from app.admin import admin_bp
from app.settings import SECRET_KEY


def create_app() -> Flask:
    app = Flask(__name__)

    # Secret key for session/flash
    app.config["SECRET_KEY"] = SECRET_KEY or os.environ.get("SECRET_KEY") or "dev-secret"

    # Register blueprints
    app.register_blueprint(admin_bp)

    # Jinja: human-readable timestamp filter
    @app.template_filter("humants")
    def _human_ts(value):
        """
        Convert epoch seconds to human-readable UTC string.
        Usage in templates: {{ quiz.updated_at|humants }}
        """
        try:
            if value is None:
                return "—"
            return datetime.utcfromtimestamp(int(value)).strftime("%Y-%m-%d %H:%M:%S UTC")
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
