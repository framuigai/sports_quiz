import os
import firebase_admin
from firebase_admin import credentials, firestore

# Use the service-account file relative to this script
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # .../backend
SA_PATH = os.path.join(BASE_DIR, "credentials", "service_account.json")


print(BASE_DIR, SA_PATH)

if not os.path.exists(SA_PATH):
    raise FileNotFoundError(f"Service account not found at: {SA_PATH}")

cred = credentials.Certificate(SA_PATH)
firebase_admin.initialize_app(cred)
db = firestore.client()


now = firestore.SERVER_TIMESTAMP

docs = [
    {"id": "admin_quiz_1", "title": "Champions League Legends", "is_admin_quiz": True, "available_to_all": True, "is_approved": True, "deleted": 0, "owner_id": "admin", "created_at": now},
    {"id": "admin_quiz_2", "title": "AFCON Classics", "is_admin_quiz": True, "available_to_all": True, "is_approved": True, "deleted": 0, "owner_id": "admin", "created_at": now},
    {"id": "user_quiz_private_1", "title": "My Club History (Private)", "is_admin_quiz": False, "available_to_all": False, "is_approved": True, "deleted": 0, "owner_id": "wObXJ137R4QrCviWeJPUJomE3a93", "created_at": now},
]

batch = db.batch()
for d in docs:
    ref = db.collection("quizzes").document(d["id"])
    batch.set(ref, d)
batch.commit()

print("✅ Seeded quizzes successfully.")
