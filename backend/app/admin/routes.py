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
        count = 0
        for _ in q.stream():
            count += 1
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


# =====================================================================
#                           QUESTIONS CRUD
#   Storage: quizzes/{doc_id}/questions/{qid}
#   Using "order" (not "index") + booleans + server timestamps
# =====================================================================

def _as_int(value: Any, fallback: int = 0) -> int:
    try:
        if isinstance(value, bool):
            return int(value)
        return int(value)
    except Exception:
        return fallback


def _split_4(texts: List[str]) -> List[str]:
    """Ensure exactly 4 trimmed strings; pad with empty if fewer; truncate if more."""
    out = [(t or "").strip() for t in texts]
    if len(out) < 4:
        out += [""] * (4 - len(out))
    return out[:4]


def _validate_question_payload(form: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate and normalize question payload from form.
    Expected inputs:
      - order (int >= 0)
      - text (non-empty)
      - options[0..3] (non-empty strings; exactly 4)
      - correct_index (0..3)
      - image_url (optional)
    Returns a dict ready to write to Firestore.
    Raises ValueError with readable messages if invalid.
    """
    order_raw = (form.get("order") or form.get("index") or "").strip()
    text = (form.get("text") or "").strip()
    opt0 = (form.get("options_0") or "").strip()
    opt1 = (form.get("options_1") or "").strip()
    opt2 = (form.get("options_2") or "").strip()
    opt3 = (form.get("options_3") or "").strip()
    correct_raw = (form.get("correct_index") or "").strip()
    image_url = (form.get("image_url") or "").strip()

    if not text:
        raise ValueError("Question text is required.")

    order = _as_int(order_raw, fallback=-1)
    if order < 0:
        raise ValueError("Order must be a non-negative integer.")

    options = _split_4([opt0, opt1, opt2, opt3])
    if any(o == "" for o in options):
        raise ValueError("All 4 options are required (no blanks).")

    correct_index = _as_int(correct_raw, fallback=-1)
    if correct_index not in (0, 1, 2, 3):
        raise ValueError("correct_index must be one of 0, 1, 2, 3.")

    return {
        "order": order,
        "text": text,
        "options": options,           # stored as array in Firestore
        "correct_index": correct_index,
        "image_url": image_url,
        "active": True,
        "deleted": False,
        # timestamps set by caller; created_at on create, updated_at always
    }


@admin_bp.route("/quizzes/<doc_id>/questions")
def questions_list(doc_id: str):
    """
    List all questions for a quiz ordered by order (fallback: index).
    """
    # Ensure quiz exists
    quiz_snap = _quiz_ref(doc_id).get()
    if not quiz_snap.exists:
        raise NotFound("Quiz not found")

    items: List[Dict[str, Any]] = []
    try:
        # Prefer 'order'; if missing index, Firestore will still return docs but not sorted by it.
        q = _question_collection(doc_id).order_by("order")
        for snap in q.stream():
            data = snap.to_dict() or {}
            data["id"] = snap.id
            # defaults for template resilience
            data.setdefault("image_url", "")
            data.setdefault("correct_index", 0)
            data.setdefault("order", data.get("index", 0))
            data.setdefault("updated_at", 0)
            items.append(data)
    except Exception:
        # Fallback: try legacy "index"
        try:
            q = _question_collection(doc_id).order_by("index")
            for snap in q.stream():
                data = snap.to_dict() or {}
                data["id"] = snap.id
                data.setdefault("image_url", "")
                data.setdefault("correct_index", 0)
                data.setdefault("order", data.get("index", 0))
                data.setdefault("updated_at", 0)
                items.append(data)
        except Exception as e:
            flash(f"Failed to load questions: {e}", "error")

    # For header/meta
    quiz = quiz_snap.to_dict() or {}
    quiz["id"] = quiz_snap.id
    quiz.setdefault("title", "—")
    quiz.setdefault("difficulty", "easy")

    return render_template(
        "questions.html",
        quiz=quiz,
        items=items,
    )


@admin_bp.route("/quizzes/<doc_id>/questions/new", methods=["GET", "POST"])
def question_new(doc_id: str):
    """
    Create a new question.
    """
    # Ensure quiz exists
    quiz_snap = _quiz_ref(doc_id).get()
    if not quiz_snap.exists:
        raise NotFound("Quiz not found")

    quiz = quiz_snap.to_dict() or {}
    quiz["id"] = doc_id

    if request.method == "GET":
        # Render empty form
        return render_template(
            "question_form.html",
            quiz=quiz,
            question=None,
            mode="create",
        )

    # POST - validate and insert
    try:
        payload = _validate_question_payload(request.form)
        payload["created_at"] = SERVER_TIMESTAMP
        payload["updated_at"] = SERVER_TIMESTAMP
        _question_collection(doc_id).add(payload)

        # Optional: update denormalized num_questions
        try:
            q = (
                _question_collection(doc_id)
                .where(filter=FieldFilter("deleted", "==", False))
                .where(filter=FieldFilter("active", "==", True))
            )
            cnt = 0
            for _ in q.stream():
                cnt += 1
            _quiz_ref(doc_id).update(
                {"num_questions": cnt, "updated_at": SERVER_TIMESTAMP}
            )
        except Exception:
            pass

        flash("Question created.", "success")
        return redirect(url_for("admin.questions_list", doc_id=doc_id))
    except ValueError as ve:
        flash(str(ve), "error")
        return redirect(url_for("admin.question_new", doc_id=doc_id))
    except Exception as e:
        flash(f"Failed to create question: {e}", "error")
        return redirect(url_for("admin.question_new", doc_id=doc_id))


@admin_bp.route("/quizzes/<doc_id>/questions/<qid>/edit", methods=["GET", "POST"])
def question_edit(doc_id: str, qid: str):
    """
    Edit a question.
    """
    # Ensure quiz exists
    quiz_snap = _quiz_ref(doc_id).get()
    if not quiz_snap.exists:
        raise NotFound("Quiz not found")
    quiz = quiz_snap.to_dict() or {}
    quiz["id"] = doc_id

    # Ensure question exists
    qref = _question_collection(doc_id).document(qid)
    qsnap = qref.get()
    if not qsnap.exists:
        raise NotFound("Question not found")

    if request.method == "GET":
        question = qsnap.to_dict() or {}
        question["id"] = qid
        # Normalize for template fields
        question.setdefault("order", question.get("index", 0))
        question.setdefault("text", "")
        question.setdefault("options", ["", "", "", ""])
        question.setdefault("correct_index", 0)
        question.setdefault("image_url", "")
        return render_template(
            "question_form.html",
            quiz=quiz,
            question=question,
            mode="edit",
        )

    # POST - validate and update
    try:
        payload = _validate_question_payload(request.form)
        # Ensure created_at preserved; set server updated_at
        existing = qsnap.to_dict() or {}
        created_at = existing.get("created_at", SERVER_TIMESTAMP)
        payload["created_at"] = created_at
        payload["updated_at"] = SERVER_TIMESTAMP
        qref.set(payload, merge=False)

        # Optional: update denormalized num_questions
        try:
            q = (
                _question_collection(doc_id)
                .where(filter=FieldFilter("deleted", "==", False))
                .where(filter=FieldFilter("active", "==", True))
            )
            cnt = 0
            for _ in q.stream():
                cnt += 1
            _quiz_ref(doc_id).update(
                {"num_questions": cnt, "updated_at": SERVER_TIMESTAMP}
            )
        except Exception:
            pass

        flash("Question updated.", "success")
        return redirect(url_for("admin.questions_list", doc_id=doc_id))
    except ValueError as ve:
        flash(str(ve), "error")
        return redirect(url_for("admin.question_edit", doc_id=doc_id, qid=qid))
    except Exception as e:
        flash(f"Failed to update question: {e}", "error")
        return redirect(url_for("admin.question_edit", doc_id=doc_id, qid=qid))


@admin_bp.route("/quizzes/<doc_id>/questions/<qid>/delete", methods=["POST"])
def question_delete(doc_id: str, qid: str):
    """
    HARD delete a question (current approach).
    NOTE: Switching to soft-delete later: set deleted=True, updated_at=SERVER_TIMESTAMP
    """
    try:
        _question_collection(doc_id).document(qid).delete()

        # Optional: update denormalized num_questions
        try:
            q = (
                _question_collection(doc_id)
                .where(filter=FieldFilter("deleted", "==", False))
                .where(filter=FieldFilter("active", "==", True))
            )
            cnt = 0
            for _ in q.stream():
                cnt += 1
            _quiz_ref(doc_id).update(
                {"num_questions": cnt, "updated_at": SERVER_TIMESTAMP}
            )
        except Exception:
            pass

        flash("Question deleted.", "success")
    except Exception as e:
        flash(f"Failed to delete question: {e}", "error")
    return redirect(url_for("admin.questions_list", doc_id=doc_id))
