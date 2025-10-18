import firebase_admin
from firebase_admin import credentials, firestore

# Initialize Firebase using Application Default Credentials
cred = credentials.ApplicationDefault()
firebase_admin.initialize_app(cred)
db = firestore.client()

now = firestore.SERVER_TIMESTAMP

docs = [
    {"id": "admin_quiz_1", "title": "Champions League Legends", "is_admin_quiz": True, "available_to_all": True, "is_approved": True, "deleted": 0, "owner_id": "admin", "created_at": now},
    {"id": "admin_quiz_2", "title": "AFCON Classics", "is_admin_quiz": True, "available_to_all": True, "is_approved": True, "deleted": 0, "owner_id": "admin", "created_at": now},
    {"id": "user_quiz_private_1", "title": "My Club History (Private)", "is_admin_quiz": False, "available_to_all": False, "is_approved": True, "deleted": 0, "owner_id": "<YOUR_TEST_UID>", "created_at": now},
]

batch = db.batch()
for d in docs:
    ref = db.collection("quizzes").document(d["id"])
    batch.set(ref, d)
batch.commit()

print("✅ Seeded quizzes successfully.")
