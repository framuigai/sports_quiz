# backend/app/admin/routes.py
from __future__ import annotations

import time
from typing import Any, Dict, List

from flask import (
    Blueprint,
    render_template,
    request,
    redirect,
    url_for,
    flash,
    abort,
)
from google.cloud import firestore
from werkzeug.exceptions import NotFound
from google.cloud.firestore_v1 import FieldFilter, SERVER_TIMESTAMP
from app.firebase_client import get_db
from app.settings import ADMIN_SECRET

# Blueprint for /admin with its own template folder
admin_bp = Blueprint(
    "admin",
    __name__,
    url_prefix="/admin",
    template_folder="templates",
)

# -----------------------------
# Helpers (also reused by questions.py via import)
# -----------------------------
def _now() -> int:
    """Return current time in epoch seconds (int)."""
    return int(time.time())


def _db() -> firestore.Client:
    """Firestore client (singleton via firebase_client)."""
    return get_db()


def _quiz_ref(doc_id: str) -> firestore.DocumentReference:
    return _db().collection("quizzes").document(doc_id)


def _question_collection(quiz_id: str) -> firestore.CollectionReference:
    """Return the subcollection reference for questions of a quiz."""
    return _quiz_ref(quiz_id).collection("questions")


def _build_base_query(
    include_deleted: bool,
    include_unapproved: bool,
    only_admin: bool,
) -> firestore.Query:
    q = _db().collection("quizzes")
    if only_admin:
        q = q.where(filter=FieldFilter("is_admin_quiz", "==", True))
    if not include_unapproved:
        q = q.where(filter=FieldFilter("is_approved", "==", True))
    if not include_deleted:
        q = q.where(filter=FieldFilter("deleted", "==", False))
    # Order by updated_at DESC to mirror mobile
    q = q.order_by("updated_at", direction=firestore.Query.DESCENDING)
    return q


def _admin_guard_ok(req: request) -> bool:
    """
    Minimal optional guard using a header or query param for development.
    If ADMIN_SECRET is unset, allow access (dev-friendly).
    If set, require header X-Admin-Secret or ?admin_secret=... to match.
    """
    if not ADMIN_SECRET:
        return True
    provided = req.headers.get("X-Admin-Secret") or req.args.get("admin_secret")
    return provided == ADMIN_SECRET


@admin_bp.before_request
def _enforce_admin_guard():
    # Only guard the /admin area; skip static, etc.
    if not _admin_guard_ok(request):
        # Avoid redirect loops — return 403 directly
        abort(403)


# -----------------------------
# Dashboard & Attempts (basic)
# -----------------------------
@admin_bp.route("/")
def dashboard():
    return render_template("dashboard.html")


@admin_bp.route("/attempts")
def attempts():
    return render_template("attempts.html")


# -----------------------------
# Quizzes: List with filters
# -----------------------------
@admin_bp.route("/quizzes")
def quizzes():
    include_deleted = request.args.get("include_deleted", "0") == "1"
    include_unapproved = request.args.get("include_unapproved", "1") == "1"
    only_admin = request.args.get("only_admin", "1") == "1"

    try:
        query = _build_base_query(
            include_deleted=include_deleted,
            include_unapproved=include_unapproved,
            only_admin=only_admin,
        )
        items: List[Dict[str, Any]] = []
        for snap in query.stream():
            data = snap.to_dict() or {}
            data["id"] = snap.id
            # Ensure defaults exist for template
            data.setdefault("deleted", False)
            data.setdefault("available_to_all", False)
            data.setdefault("is_approved", False)
            data.setdefault("difficulty", "easy")
            items.append(data)

        return render_template(
            "quizzes.html",
            items=items,
            include_deleted=include_deleted,
            include_unapproved=include_unapproved,
            only_admin=only_admin,
        )
    except Exception as e:
        flash(f"Failed to load quizzes: {e}", "error")
        return render_template(
            "quizzes.html",
            items=[],
            include_deleted=include_deleted,
            include_unapproved=include_unapproved,
            only_admin=only_admin,
        )


# -----------------------------
# NEW: AI Drafts List
# -----------------------------
@admin_bp.route("/ai_drafts")
def ai_drafts():
    try:
        q = (
            _db()
            .collection("quizzes")
            .where(filter=FieldFilter("is_admin_quiz", "==", True))
            .where(filter=FieldFilter("is_approved", "==", False))
            .where(filter=FieldFilter("deleted", "==", False))
            .order_by("updated_at", direction=firestore.Query.DESCENDING)
        )
        items: List[Dict[str, Any]] = []
        for snap in q.stream():
            data = snap.to_dict() or {}
            data["id"] = snap.id
            # Safe defaults for template
            data.setdefault("title", "(untitled)")
            data.setdefault("description", "")
            data.setdefault("difficulty", "easy")
            data.setdefault("available_to_all", False)
            data.setdefault("is_approved", False)
            data.setdefault("num_questions", None)
            data.setdefault("source", "ai")
            items.append(data)

        return render_template("ai_drafts.html", items=items)
    except Exception as e:
        flash(f"Failed to load AI drafts: {e}", "error")
        return render_template("ai_drafts.html", items=[])


# -----------------------------
# NEW: Publish Draft (Approve + Make Global)
# -----------------------------
@admin_bp.route("/quizzes/<doc_id>/publish", methods=["POST"])
def publish_quiz(doc_id: str):
    ref = _quiz_ref(doc_id)
    try:
        ref.update(
            {
                "is_approved": True,
                "available_to_all": True,
                "updated_at": SERVER_TIMESTAMP,
            }
        )
        flash("Draft approved & published.", "success")
    except Exception as e:
        flash(f"Failed to publish: {e}", "error")
    return redirect(url_for("admin.ai_drafts"))


# -----------------------------
# Create Quiz (GET / POST)
# -----------------------------
@admin_bp.route("/quizzes/new", methods=["GET", "POST"])
def create_quiz():
    if request.method == "GET":
        return render_template("quiz_new.html")

    # POST
    try:
        title = (request.form.get("title") or "").strip()
        description = (request.form.get("description") or "").strip()
        difficulty = (request.form.get("difficulty") or "easy").strip().lower()

        available_to_all = request.form.get("available_to_all") == "on"
        is_approved = request.form.get("is_approved") == "on"

        if not title:
            flash("Title is required.", "error")
            return redirect(url_for("admin.create_quiz"))

        doc = {
            "title": title,
            "description": description,
            "difficulty": difficulty or "easy",
            "is_admin_quiz": True,
            "available_to_all": bool(available_to_all),
            "is_approved": bool(is_approved),
            "deleted": False,
            "created_at": SERVER_TIMESTAMP,
            "updated_at": SERVER_TIMESTAMP,
            # Optional denormalized fields you might add later:
            # "version": 1,
            # "num_questions": 0,
            # "source": "manual_admin"
        }

        _db().collection("quizzes").add(doc)
        flash("Quiz created.", "success")
        return redirect(url_for("admin.quizzes"))
    except Exception as e:
        flash(f"Failed to create quiz: {e}", "error")
        return redirect(url_for("admin.create_quiz"))


# -----------------------------
# Quiz Detail (with questions_count)
# -----------------------------
@admin_bp.route("/quizzes/<doc_id>")
def quiz_detail(doc_id: str):
    snap = _quiz_ref(doc_id).get()
    if not snap.exists:
        raise NotFound("Quiz not found")
    quiz = snap.to_dict() or {}
    quiz["id"] = snap.id
    quiz.setdefault("deleted", False)
    quiz.setdefault("available_to_all", False)
    quiz.setdefault("is_approved", False)
    quiz.setdefault("difficulty", "easy")

    # Compute questions_count (active & not deleted)
    try:
        q = (
            _question_collection(doc_id)
            .where(filter=FieldFilter("deleted", "==", False))
            .where(filter=FieldFilter("active", "==", True))
        )
        count = sum(1 for _ in q.stream())
        questions_count = count
    except Exception as e:
        questions_count = None
        flash(f"Failed to compute questions count: {e}", "warning")

    return render_template("quiz_detail.html", quiz=quiz, questions_count=questions_count)


# -----------------------------
# Toggle Available
# -----------------------------
@admin_bp.route("/quizzes/<doc_id>/toggle-available", methods=["POST"])
def toggle_available(doc_id: str):
    ref = _quiz_ref(doc_id)
    try:
        @firestore.transactional
        def txn_op(tx: firestore.Transaction):
            snap = tx.get(ref)
            if not snap.exists:
                raise NotFound("Quiz not found")
            data = snap.to_dict() or {}
            current = bool(data.get("available_to_all", False))
            tx.update(ref, {"available_to_all": not current, "updated_at": SERVER_TIMESTAMP})

        txn = _db().transaction()
        txn_op(txn)
        flash("Availability toggled.", "success")
    except Exception as e:
        flash(f"Failed to toggle availability: {e}", "error")
    return redirect(url_for("admin.quiz_detail", doc_id=doc_id))


# -----------------------------
# Soft Delete / Restore (quiz-level)
# -----------------------------
@admin_bp.route("/quizzes/<doc_id>/soft-delete", methods=["POST"])
def soft_delete_quiz(doc_id: str):
    try:
        _quiz_ref(doc_id).update({"deleted": True, "updated_at": SERVER_TIMESTAMP})
        flash("Quiz soft-deleted.", "success")
    except Exception as e:
        flash(f"Failed to soft-delete: {e}", "error")
    return redirect(url_for("admin.quiz_detail", doc_id=doc_id))


@admin_bp.route("/quizzes/<doc_id>/restore", methods=["POST"])
def restore_quiz(doc_id: str):
    try:
        _quiz_ref(doc_id).update({"deleted": False, "updated_at": SERVER_TIMESTAMP})
        flash("Quiz restored.", "success")
    except Exception as e:
        flash(f"Failed to restore: {e}", "error")
    return redirect(url_for("admin.quiz_detail", doc_id=doc_id))


# ----------------------------------------------------------------------
# Import question routes last, after admin_bp and helpers exist.
# This avoids circular import issues and keeps URLs unchanged.
# ----------------------------------------------------------------------
from .questions import *  # noqa: E402,F401,F403  (registers question routes on admin_bp)
