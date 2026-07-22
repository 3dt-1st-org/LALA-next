from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

_TAG_MAX_LEN = 32
_TAGS_MAX_COUNT = 8


def _normalize_tags(tags: list[str] | None) -> list[str]:
    """Trim, de-duplicate, strip leading '#', and cap the tag count.

    Mirrors the GEOND_OPIc ``_clean_tags`` helper so the wire format stays
    compatible while keeping the contract defensive against malformed input.
    """
    cleaned: list[str] = []
    for raw in tags or []:
        value = str(raw).strip().lstrip("#").strip()[:_TAG_MAX_LEN]
        if value and value not in cleaned:
            cleaned.append(value)
        if len(cleaned) >= _TAGS_MAX_COUNT:
            break
    return cleaned


class CommunityPostCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=160)
    body: str = Field(..., min_length=1, max_length=4000)
    tags: list[str] | None = None

    @field_validator("tags")
    @classmethod
    def _clean_tags(cls, value: list[str] | None) -> list[str]:
        return _normalize_tags(value)


class CommunityCommentCreate(BaseModel):
    body: str = Field(..., min_length=1, max_length=1200)


class CommunityFollowCreate(BaseModel):
    followee_issuer: str = Field(..., min_length=1, max_length=256)
    followee_subject: str = Field(..., min_length=1, max_length=256)


class CommunityPostResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    author_user_id: UUID
    title: str
    body: str
    tags: list[str]
    comment_count: int
    like_count: int
    viewer_liked: bool
    created_at: datetime
    updated_at: datetime


class CommunityPostListResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    count: int
    posts: list[CommunityPostResponse]


class CommunityCommentResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    post_id: UUID
    author_user_id: UUID
    body: str
    created_at: datetime
    updated_at: datetime


class CommunityCommentListResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    count: int
    comments: list[CommunityCommentResponse]


class CommunityLikeResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    post_id: UUID
    liked: bool
    like_count: int


class CommunityFollowResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    followee_user_id: UUID
    created_at: datetime


class CommunityFollowListResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    count: int
    follows: list[CommunityFollowResponse]


class CommunityFollowToggleResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    followee_user_id: UUID | None
    following: bool
