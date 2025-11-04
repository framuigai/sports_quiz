# backend/app/ai/schema.py
from __future__ import annotations

from typing import List, Optional
from pydantic import BaseModel, Field, conlist, field_validator


class QuestionIn(BaseModel):
    order: int = Field(ge=0)
    text: str = Field(min_length=1)
    options: conlist(str, min_length=4, max_length=4)
    correct_index: int = Field(ge=0, le=3)
    image_url: Optional[str] = ""

    # Normalize trim
    @field_validator("text", mode="before")
    def _trim_text(cls, v):
        return (v or "").strip()

    @field_validator("options", mode="before")
    def _trim_options(cls, v):
        return [str(x or "").strip() for x in v]


class QuizIn(BaseModel):
    title: str = Field(min_length=1)
    description: Optional[str] = ""
    difficulty: str = Field(default="easy")  # "easy" | "medium" | "hard"
    questions: List[QuestionIn]

    @field_validator("title", "description", "difficulty", mode="before")
    def _trim_texts(cls, v):
        return (v or "").strip()

    @field_validator("difficulty")
    def _difficulty_enum(cls, v):
        allowed = {"easy", "medium", "hard"}
        vv = (v or "").lower()
        if vv not in allowed:
            return "easy"
        return vv


class QuizWrite(BaseModel):
    """
    Final shape for Firestore write (quizzes document).
    """
    title: str
    description: str
    difficulty: str
    is_admin_quiz: bool = False
    available_to_all: bool = False
    is_approved: bool = True
    deleted: bool = False
    source: str = "ai"
    owner_id: Optional[str] = None
    num_questions: Optional[int] = None
