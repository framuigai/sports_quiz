# backend/app/settings.py
from __future__ import annotations

import os

# Project / Firebase
FIREBASE_PROJECT_ID = os.getenv("FIREBASE_PROJECT_ID", "").strip() or None

# Service account path (backend/app/credentials/service-account.json recommended)
GOOGLE_APPLICATION_CREDENTIALS = os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "").strip() or None

# Firestore emulator (e.g., "localhost:8080"). If set, client connects to emulator.
FIRESTORE_EMULATOR_HOST = os.getenv("FIRESTORE_EMULATOR_HOST", "").strip() or None

# Flask secret for flash/session
SECRET_KEY = os.getenv("SECRET_KEY", "").strip() or None

# Optional simple admin guard secret.
# If set, requests to /admin must include:
#   Header: X-Admin-Secret: <value>
#   OR query param: ?admin_secret=<value>
ADMIN_SECRET = os.getenv("ADMIN_SECRET", "").strip() or None

# === Gemini / Generative AI ===
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "").strip() or None
