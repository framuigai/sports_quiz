from __future__ import annotations

import os
from functools import lru_cache
from typing import Optional

from google.cloud import firestore
from google.oauth2 import service_account

from app.settings import (
    FIREBASE_PROJECT_ID,
    GOOGLE_APPLICATION_CREDENTIALS,
    FIRESTORE_EMULATOR_HOST,
)


@lru_cache(maxsize=1)
def get_db() -> firestore.Client:
    """
    Returns a singleton Firestore Client.

    Priority:
      1) If FIRESTORE_EMULATOR_HOST is set -> connect to emulator
      2) If GOOGLE_APPLICATION_CREDENTIALS points to a file -> use those creds
      3) Else fallback to default application credentials
    """
    # Emulator support
    if FIRESTORE_EMULATOR_HOST:
        # For emulator, a plain client is enough; project can be supplied.
        return firestore.Client(project=FIREBASE_PROJECT_ID)

    # Explicit service account
    if GOOGLE_APPLICATION_CREDENTIALS and os.path.isfile(GOOGLE_APPLICATION_CREDENTIALS):
        creds = service_account.Credentials.from_service_account_file(GOOGLE_APPLICATION_CREDENTIALS)
        return firestore.Client(project=FIREBASE_PROJECT_ID, credentials=creds)

    # Default ADC (gcloud auth application-default login, Cloud Run, etc.)
    return firestore.Client(project=FIREBASE_PROJECT_ID)
