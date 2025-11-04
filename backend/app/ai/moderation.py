# backend/app/ai/moderation.py
from __future__ import annotations

from typing import Any, Dict, List, Tuple


def moderate_quiz(obj: Dict[str, Any]) -> Tuple[bool, List[str]]:
    """
    Very light moderation stub. Extend as needed (PII, profanity, slurs, etc.).
    Returns (ok, reasons[]).
    """
    reasons: List[str] = []

    title = (obj.get("title") or "").lower()
    if any(bad in title for bad in ["nsfw", "explicit"]):
        reasons.append("title contains disallowed content")

    # You can also loop through questions to check text/options.

    return (len(reasons) == 0, reasons)
