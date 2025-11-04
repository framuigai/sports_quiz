# backend/app/ai/routes.py
from __future__ import annotations

from typing import Any, Dict

from flask import Blueprint, jsonify, request
from google.cloud.firestore_v1 import SERVER_TIMESTAMP

from app.firebase_client import get_db
from app.settings import ADMIN_SECRET
from .generator import generate_quiz_payload
from .schema import QuizWrite
from app.ai.moderation import moderate_quiz

ai_bp = Blueprint("ai", __name__)


def _bool(v: Any) -> bool:
    return str(v).lower() in {"1", "true", "t", "yes"}


def _admin_guard_ok(req) -> bool:
    """
    Optional simple guard if you want to keep this endpoint private.
    If ADMIN_SECRET is set, require X-Admin-Secret header or ?admin_secret=...
    """
    if not ADMIN_SECRET:
        return True
    provided = req.headers.get("X-Admin-Secret") or req.args.get("admin_secret")
    return provided == ADMIN_SECRET


@ai_bp.route("/generate_quiz", methods=["POST"])
def generate_quiz():
    if not _admin_guard_ok(request):
        return jsonify({"error": "forbidden"}), 403

    payload = request.get_json(silent=True) or {}
    topic = (payload.get("topic") or "").strip()
    difficulty = (payload.get("difficulty") or "easy").strip().lower()
    num_questions = int(payload.get("num_questions") or 10)

    # Flow control
    # mode = "user" or "admin"
    mode = (payload.get("mode") or "user").strip().lower()
    owner_id = (payload.get("owner_id") or "").strip() or None

    if not topic:
        return jsonify({"error": "topic is required"}), 400

    try:
        quiz_in = generate_quiz_payload(topic, difficulty, num_questions)

        # Basic moderation hook (can be extended)
        ok, reasons = moderate_quiz(quiz_in.model_dump())
        if not ok:
            return jsonify({"error": "blocked_by_moderation", "reasons": reasons}), 400

        db = get_db()
        quiz_doc = QuizWrite(
            title=quiz_in.title,
            description=quiz_in.description or "",
            difficulty=quiz_in.difficulty,
            is_admin_quiz=(mode == "admin"),
            available_to_all=False,
            is_approved=(mode == "user"),  # user-private quizzes are immediately approved
            deleted=False,
            source="ai",
            owner_id=owner_id if mode == "user" else None,
            num_questions=len(quiz_in.questions),
        ).model_dump()

        # Timestamps
        quiz_doc["created_at"] = SERVER_TIMESTAMP
        quiz_doc["updated_at"] = SERVER_TIMESTAMP

        # Create quiz
        quiz_ref = db.collection("quizzes").document()
        quiz_ref.set(quiz_doc)

        # Create questions
        qcol = quiz_ref.collection("questions")
        batch = db.batch()
        for q in quiz_in.questions:
            qdoc = {
                "order": int(q.order),
                "text": q.text,
                "options": list(q.options),
                "correct_index": int(q.correct_index),
                "image_url": q.image_url or "",
                "active": True,
                "deleted": False,
                "created_at": SERVER_TIMESTAMP,
                "updated_at": SERVER_TIMESTAMP,
            }
            qref = qcol.document()
            batch.set(qref, qdoc)

        batch.commit()

        return jsonify({"quiz_id": quiz_ref.id}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500
