# backend/app/ai/generator.py
from __future__ import annotations

import json
from typing import Tuple

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
    return genai.GenerativeModel("gemini-1.5-flash")


def generate_quiz_payload(topic: str, difficulty: str, num_questions: int) -> QuizIn:
    model = init_genai()
    contents = [
        {"role": "system", "parts": [SYSTEM_PROMPT]},
        {"role": "user", "parts": [_build_user_prompt(topic, difficulty, num_questions)]},
    ]
    resp = model.generate_content(contents)
    if resp is None or resp.text is None:
        raise RuntimeError("Empty response from Gemini")

    # Some SDKs wrap JSON in ``` blocks; be resilient
    raw = resp.text.strip()
    if raw.startswith("```"):
        raw = raw.strip("`")
        # remove possible "json" header
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

    # Normalize orders if model didn't give perfect sequence
    for i, q in enumerate(quiz_in.questions):
        q.order = i

    return quiz_in
