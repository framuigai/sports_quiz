# backend/app/ai/generator.py
from __future__ import annotations

import json
import random

import google.generativeai as genai
from pydantic import ValidationError

from app.settings import GEMINI_API_KEY
from .schema import QuizIn


SYSTEM_PROMPT = """You are an assistant that generates multiple-choice sports quizzes.
STRICTLY return JSON only (no markdown, no commentary).
Schema:
{
  "title": "string",
  "description": "string",
  "difficulty": "easy|medium|hard",
  "questions": [
    {
      "order": 0,
      "text": "string",
      "options": ["string", "string", "string", "string"],
      "correct_index": 0,
      "image_url": "string or empty"
    }
  ]
}
Constraints:
- Exactly 4 options per question.
- correct_index must be 0..3 and match the correct option.
- order is a 0-based integer that increases by 1 for each question.
- Keep language simple, unambiguous, and suitable for a general audience.
- Do not include explanations or extra fields.
- Return JSON only.
"""


def _build_user_prompt(topic: str, difficulty: str, num_questions: int) -> str:
    return json.dumps({
        "topic": topic,
        "difficulty": difficulty,
        "num_questions": max(1, min(20, int(num_questions))),
        "notes": "Return strictly JSON matching the schema and constraints."
    })


def init_genai():
    if not GEMINI_API_KEY:
        raise RuntimeError("GEMINI_API_KEY is not set")
    genai.configure(api_key=GEMINI_API_KEY)
    # Use system_instruction instead of a 'system' role in contents
    return genai.GenerativeModel(
        model_name="gemini-2.5-flash",
        system_instruction=SYSTEM_PROMPT,
    )


def _shuffle_question_options_inplace(q) -> None:
    """
    Shuffle q.options in-place and remap q.correct_index accordingly.
    """
    # Pair original indices with option strings
    indexed_opts = list(enumerate(list(q.options)))
    random.shuffle(indexed_opts)
    # Build new options list
    q.options = [opt for _, opt in indexed_opts]
    # Find where the original correct index landed
    for new_idx, (old_idx, _) in enumerate(indexed_opts):
        if old_idx == q.correct_index:
            q.correct_index = new_idx
            break


def _postprocess_quiz(quiz_in: QuizIn) -> QuizIn:
    """
    Normalize order and randomize answer positions to avoid all 'A' correct.
    """
    # Ensure perfect 0..N-1 order
    for i, q in enumerate(quiz_in.questions):
        q.order = i

    # Always shuffle options to spread correct answers across A/B/C/D
    # (You could make this conditional if you prefer.)
    for q in quiz_in.questions:
        _shuffle_question_options_inplace(q)

    return quiz_in


def generate_quiz_payload(topic: str, difficulty: str, num_questions: int) -> QuizIn:
    model = init_genai()

    # With system_instruction set on the model, pass the user prompt directly.
    resp = model.generate_content(_build_user_prompt(topic, difficulty, num_questions))
    if resp is None or resp.text is None:
        raise RuntimeError("Empty response from Gemini")

    raw = resp.text.strip()

    # Some SDKs/models occasionally wrap JSON in ``` blocks; be resilient.
    if raw.startswith("```"):
        # remove leading & trailing backticks
        raw = raw.strip("`")
        # remove optional leading 'json'
        if raw.lower().startswith("json"):
            raw = raw[4:].strip()

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"Model returned invalid JSON: {e}")

    try:
        quiz_in = QuizIn.model_validate(data)
    except ValidationError as ve:
        raise RuntimeError(f"JSON failed schema validation: {ve}")

    # Normalize & shuffle options so correct answers aren't always A
    quiz_in = _postprocess_quiz(quiz_in)
    return quiz_in
