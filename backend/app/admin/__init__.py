from __future__ import annotations

# Import the admin blueprint from routes.py so Flask can register it
from .routes import admin_bp

# This makes 'admin_bp' available when you do:
# from app.admin import admin_bp
__all__ = ["admin_bp"]
