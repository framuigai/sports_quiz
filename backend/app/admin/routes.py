from __future__ import annotations

import time
from dataclasses import asdict, dataclass
from typing import Dict, Any

from flask import (
    Blueprint,
    render_template,
    request,
    redirect,
    url_for,
    flash,
)
from google.cloud import firestore
from werkzeug.exceptions import NotFound

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
# Helpers
# -----------------------------
def _now() -> int:
    """Return current time in epoch seconds (int)."""
    return int(time.time())


def _db() -> firestore.Client:
    """Firestore client (singleton via firebase_client)."""
    return get_db()


def _quiz_ref(doc_id: str) -> firestore.DocumentReference:
    return _db().collection("quizzes").document(doc_id)


def _build_base_query(
    include_deleted: bool,
    include_unapproved: bool,
    only_admin: bool,
) -> firestore.Query:
    q = _db().collection("quizzes")
    if only_admin:
        q = q.where("is_admin_quiz", "==", True)
    if not include_unapproved:
        q = q.where("is_approved", "==", True)
    if not include_deleted:
        q = q.where("deleted", "==", 0)
    # If you add an orderBy here on a field that isn't already indexed with the wheres,
    # Firestore may prompt to create a composite index.
    q = q.order_by("created_at", direction=firestore.Query.DESCENDING)
    return q


# -----------------------------
# Optional simple guard
# -----------------------------
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
        flash("Unauthorized: missing or invalid admin secret.", "error")
        return redirect(url_for("admin.dashboard"))


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
        items = []
        for snap in query.stream():
            data = snap.to_dict() or {}
            data["id"] = snap.id
            # Firestore returns bools/ints as-is; ensure defaults exist for template
            data.setdefault("deleted", 0)
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

        now = _now()
        doc = {
            "title": title,
            "description": description,
            "difficulty": difficulty or "easy",
            "is_admin_quiz": True,
            "available_to_all": bool(available_to_all),
            "is_approved": bool(is_approved),
            "deleted": 0,
            "created_at": now,
            "updated_at": now,
        }

        _db().collection("quizzes").add(doc)
        flash("Quiz created.", "success")
        return redirect(url_for("admin.quizzes"))
    except Exception as e:
        flash(f"Failed to create quiz: {e}", "error")
        return redirect(url_for("admin.create_quiz"))


# -----------------------------
# Quiz Detail
# -----------------------------
@admin_bp.route("/quizzes/<doc_id>")
def quiz_detail(doc_id: str):
    snap = _quiz_ref(doc_id).get()
    if not snap.exists:
        raise NotFound("Quiz not found")
    quiz = snap.to_dict() or {}
    quiz["id"] = snap.id
    quiz.setdefault("deleted", 0)
    quiz.setdefault("available_to_all", False)
    quiz.setdefault("is_approved", False)
    quiz.setdefault("difficulty", "easy")
    return render_template("quiz_detail.html", quiz=quiz)


# -----------------------------
# Toggle Available
# -----------------------------
@admin_bp.route("/quizzes/<doc_id>/toggle-available", methods=["POST"])
def toggle_available(doc_id: str):
    ref = _quiz_ref(doc_id)
    try:
        def txn_op(tx: firestore.Transaction):
            snap = ref.get(transaction=tx)
            if not snap.exists:
                raise NotFound("Quiz not found")
            data = snap.to_dict() or {}
            current = bool(data.get("available_to_all", False))
            tx.update(ref, {"available_to_all": not current, "updated_at": _now()})

        _db().transaction()(txn_op)  # run transaction
        flash("Availability toggled.", "success")
    except Exception as e:
        flash(f"Failed to toggle availability: {e}", "error")
    return redirect(url_for("admin.quiz_detail", doc_id=doc_id))


# -----------------------------
# Soft Delete
# -----------------------------
@admin_bp.route("/quizzes/<doc_id>/soft-delete", methods=["POST"])
def soft_delete_quiz(doc_id: str):
    try:
        _quiz_ref(doc_id).update({"deleted": 1, "updated_at": _now()})
        flash("Quiz soft-deleted.", "success")
    except Exception as e:
        flash(f"Failed to soft-delete: {e}", "error")
    return redirect(url_for("admin.quiz_detail", doc_id=doc_id))


# -----------------------------
# Restore
# -----------------------------
@admin_bp.route("/quizzes/<doc_id>/restore", methods=["POST"])
def restore_quiz(doc_id: str):
    try:
        _quiz_ref(doc_id).update({"deleted": 0, "updated_at": _now()})
        flash("Quiz restored.", "success")
    except Exception as e:
        flash(f"Failed to restore: {e}", "error")
    return redirect(url_for("admin.quiz_detail", doc_id=doc_id))
