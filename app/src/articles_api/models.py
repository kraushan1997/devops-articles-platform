from datetime import datetime

from pydantic import BaseModel, Field


class ArticleCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    content: str = Field(..., min_length=1)
    author: str = Field(..., min_length=1, max_length=100)
    tags: list[str] = Field(default_factory=list)


class ArticleUpdate(BaseModel):
    """Every field optional: PUT applies only the fields that are sent."""

    title: str | None = Field(None, min_length=1, max_length=200)
    content: str | None = Field(None, min_length=1)
    author: str | None = Field(None, min_length=1, max_length=100)
    tags: list[str] | None = None


class ArticleOut(ArticleCreate):
    id: str
    created_at: datetime
    updated_at: datetime
