# backend/app/admin/questions.py
from __future__ import annotations

from typing import Any, Dict, List

from flask import render_template, request, redirect, url_for, flash
from werkzeug.exceptions import NotFound
from google.cloud.firestore_v1 import FieldFilter, SERVER_TIMESTAMP

# Import the existing blueprint and shared helpers from routes.py
# NOTE: routes.py imports this file at the very bottom AFTER defining admin_bp and helpers.
from .routes import admin_bp, _quiz_ref, _question_collection


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

    # Defensive final sort by 'order' in case Firestore ordering wasn't applied (legacy docs).
    items.sort(key=lambda d: int(d.get("order", 0)))

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
            cnt = sum(1 for _ in q.stream())
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
            cnt = sum(1 for _ in q.stream())
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
            cnt = sum(1 for _ in q.stream())
            _quiz_ref(doc_id).update(
                {"num_questions": cnt, "updated_at": SERVER_TIMESTAMP}
            )
        except Exception:
            pass

        flash("Question deleted.", "success")
    except Exception as e:
        flash(f"Failed to delete question: {e}", "error")
    return redirect(url_for("admin.questions_list", doc_id=doc_id))
