# backend/app/main.py
from flask import Flask                 
from flask_cors import CORS
from .api.routes import api_bp
from .ai.routes import ai_bp
from .admin.routes import admin_bp

def create_app():
    app = Flask(__name__)
    app.secret_key = "change_me"
    app.register_blueprint(api_bp, url_prefix="/")
    app.register_blueprint(ai_bp, url_prefix="/ai")
    app.register_blueprint(admin_bp, url_prefix="/admin")
    app.config["TEMPLATES_AUTO_RELOAD"] = True
    CORS(app, resources={r"/*": {"origins": "*"}})  # tighten for prod later
    return app

# 👇 expose a module-level `app` so FLASK_APP=app.main:app works
app = create_app()
