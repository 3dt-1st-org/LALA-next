from __future__ import annotations

from datetime import date, datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from apps.api.app.services.normalization import normalize_language

LocalSignalKind = Literal[
    "place_tip",
    "route_note",
    "local_question",
    "accessibility_note",
    "seasonal_update",
    "correction",
    "local_story",
]
LocalSignalLanguage = Literal["ko", "en"]
LocalityLevel = Literal["none", "province", "city", "district", "place"]
CommercialDisclosure = Literal["none", "visitor", "owner_or_staff", "paid_or_gifted"]
PlaceRelation = Literal["primary", "context", "route_stop"]
TranslationMethod = Literal["human", "machine", "community_reviewed"]
TranslationState = Literal["pending", "available", "stale", "rejected"]
LocalSignalReactionType = Literal["useful", "respectful", "needs_confirmation"]

_OPAQUE_REFERENCE = r"^[A-Za-z0-9][A-Za-z0-9:._-]{0,127}$"
OpaqueReference = Annotated[str, Field(min_length=1, max_length=128, pattern=_OPAQUE_REFERENCE)]
CanonicalPlaceId = Annotated[str, Field(min_length=1, max_length=128)]
CanonicalRegionCode = Annotated[
    str, Field(min_length=1, max_length=64, pattern=r"^[A-Za-z0-9][A-Za-z0-9:_-]{0,63}$")
]


def _strip_required_text(value: str) -> str:
    cleaned = value.strip()
    if not cleaned:
        raise ValueError("Text must not be blank.")
    return cleaned


def _normalize_signal_language(value: str) -> str:
    normalized = normalize_language(value, default="")
    if normalized not in {"ko", "en"}:
        raise ValueError("Local Signals supports Korean or English only.")
    return normalized


class LocalSignalPlaceLink(BaseModel):
    model_config = ConfigDict(extra="forbid")

    place_id: CanonicalPlaceId
    relation: PlaceRelation = "primary"


class LocalSignalDraftCreate(BaseModel):
    """Client-owned draft contract; author identity comes only from Logto."""

    model_config = ConfigDict(extra="forbid")

    kind: LocalSignalKind
    source_language: LocalSignalLanguage
    title: str = Field(min_length=1, max_length=160)
    body: str = Field(min_length=1, max_length=4000)
    locality_level: LocalityLevel = "district"
    locality_code: CanonicalRegionCode | None = None
    commercial_disclosure: CommercialDisclosure = "none"
    observation_date: date
    aggregate_opt_in: bool = False
    route_snapshot_ref: OpaqueReference | None = None
    place_links: list[LocalSignalPlaceLink] = Field(default_factory=list, max_length=8)

    @field_validator("source_language", mode="before")
    @classmethod
    def normalize_source_language(cls, value: str) -> str:
        return _normalize_signal_language(value)

    @field_validator("title", "body")
    @classmethod
    def normalize_text(cls, value: str) -> str:
        return _strip_required_text(value)

    @field_validator("place_links")
    @classmethod
    def reject_duplicate_place_links(
        cls, value: list[LocalSignalPlaceLink]
    ) -> list[LocalSignalPlaceLink]:
        keys = [(link.place_id, link.relation) for link in value]
        if len(keys) != len(set(keys)):
            raise ValueError("Place links must be unique.")
        return value


class LocalSignalTranslation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    source_language: LocalSignalLanguage
    target_language: LocalSignalLanguage
    body: str | None = Field(default=None, min_length=1, max_length=4000)
    method: TranslationMethod
    translator_version: str = Field(min_length=1, max_length=128)
    source_content_hash: str = Field(pattern=r"^[0-9a-f]{64}$")
    provenance: str = Field(min_length=1, max_length=128)
    review_state: TranslationState
    reviewed_at: datetime | None = None

    @field_validator("target_language")
    @classmethod
    def target_must_differ_from_source(
        cls, value: LocalSignalLanguage, info
    ) -> LocalSignalLanguage:
        source_language = info.data.get("source_language")
        if source_language == value:
            raise ValueError("A translation target must differ from the source language.")
        return value


class LocalSignalPublicPlaceLink(BaseModel):
    model_config = ConfigDict(extra="forbid")

    place_id: CanonicalPlaceId
    relation: PlaceRelation


class LocalSignalPublicItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    kind: LocalSignalKind
    source_language: LocalSignalLanguage
    title: str
    body: str
    locality_level: LocalityLevel
    locality_code: CanonicalRegionCode | None = None
    commercial_disclosure: CommercialDisclosure
    observation_date: date
    published_at: datetime
    place_links: list[LocalSignalPublicPlaceLink] = Field(default_factory=list)
    translation: LocalSignalTranslation | None = None
    # ``body`` is always the single body selected for the requested locale.
    display_language: LocalSignalLanguage | None = None
    translation_available: bool = False
    reaction_count: int = Field(default=0, ge=0)
    comment_count: int = Field(default=0, ge=0)


class LocalSignalFeedContext(BaseModel):
    model_config = ConfigDict(extra="forbid")

    language: LocalSignalLanguage
    locality_level: LocalityLevel | None = None
    locality_code: CanonicalRegionCode | None = None
    kind: LocalSignalKind | None = None
    sort: Literal["recent", "useful"] = "recent"


class LocalSignalFeedResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: list[LocalSignalPublicItem]
    next_cursor: OpaqueReference | None = None
    has_more: bool
    context: LocalSignalFeedContext


class LocalSignalPublicComment(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    source_language: LocalSignalLanguage
    body: str
    created_at: datetime


class LocalSignalCommentFeedResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: list[LocalSignalPublicComment]
    next_cursor: OpaqueReference | None = None
    has_more: bool
    context: LocalSignalFeedContext


class LocalSignalMutationResult(BaseModel):
    """Owner-only mutation receipt; it contains no issuer/subject or capability token."""

    model_config = ConfigDict(extra="forbid")

    id: UUID
    kind: LocalSignalKind
    status: Literal["draft", "submitted", "published", "hidden", "removed", "deleted"]
    moderation_state: Literal["unreviewed", "pending", "approved", "rejected"]
    visibility: Literal["private", "pending_review", "public", "unlisted"]
    source_language: LocalSignalLanguage
    title: str
    body: str
    locality_level: LocalityLevel
    locality_code: CanonicalRegionCode | None = None
    commercial_disclosure: CommercialDisclosure
    observation_date: date
    place_links: list[LocalSignalPublicPlaceLink] = Field(default_factory=list)


class LocalSignalPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: LocalSignalKind | None = None
    source_language: LocalSignalLanguage | None = None
    title: str | None = Field(default=None, min_length=1, max_length=160)
    body: str | None = Field(default=None, min_length=1, max_length=4000)
    locality_level: LocalityLevel | None = None
    locality_code: CanonicalRegionCode | None = None
    commercial_disclosure: CommercialDisclosure | None = None
    observation_date: date | None = None
    aggregate_opt_in: bool | None = None
    route_snapshot_ref: OpaqueReference | None = None
    place_links: list[LocalSignalPlaceLink] | None = Field(default=None, max_length=8)

    @field_validator("source_language", mode="before")
    @classmethod
    def normalize_patch_language(cls, value: str | None) -> str | None:
        if value is None:
            return None
        return _normalize_signal_language(value)

    @field_validator("title", "body")
    @classmethod
    def normalize_patch_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        return _strip_required_text(value)

    @field_validator("place_links")
    @classmethod
    def reject_duplicate_patch_links(
        cls, value: list[LocalSignalPlaceLink] | None
    ) -> list[LocalSignalPlaceLink] | None:
        if value is None:
            return None
        keys = [(link.place_id, link.relation) for link in value]
        if len(keys) != len(set(keys)):
            raise ValueError("Place links must be unique.")
        return value

    @model_validator(mode="after")
    def require_one_change(self) -> LocalSignalPatch:
        if not self.model_fields_set:
            raise ValueError("At least one signal field must be provided.")
        return self


class LocalSignalCommentCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    source_language: LocalSignalLanguage
    body: str = Field(min_length=1, max_length=1200)

    @field_validator("source_language", mode="before")
    @classmethod
    def normalize_comment_language(cls, value: str) -> str:
        return _normalize_signal_language(value)

    @field_validator("body")
    @classmethod
    def normalize_comment_body(cls, value: str) -> str:
        return _strip_required_text(value)


class LocalSignalReportCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reason_code: Literal[
        "unsafe_content",
        "privacy_exposure",
        "misleading_place",
        "promotion_not_disclosed",
        "translation_issue",
        "other_policy",
    ]


class LocalSignalPlaceAggregate(BaseModel):
    """Governed review-mention aggregate for one place and week window.

    Aggregate-only by construction: counts, an optional scalar sentiment/quality
    score, and provenance metadata. There is intentionally no field that can
    carry raw review text, an external key, an external URL, an author, or the
    source table's nested ``attributes`` blob.
    """

    model_config = ConfigDict(extra="forbid")

    # Typed system-aggregate marker: a consumer cannot mistake this row for a
    # user-generated Local Signal.
    kind: Literal["system_aggregate"] = "system_aggregate"
    place_id: CanonicalPlaceId | None = None
    place_name_ko: str = Field(min_length=1, max_length=160)
    category: str = Field(min_length=1, max_length=64)
    mention_count: int = Field(ge=0)
    organic_mention_count: int | None = Field(default=None, ge=0)
    sentiment_score: float | None = Field(default=None, ge=-1.0, le=1.0)
    review_quality_score: float | None = Field(default=None, ge=0.0, le=1.0)
    week_start: date
    week_end: date
    provider_class: Literal["aggregated_review_mentions"] = "aggregated_review_mentions"


class LocalSignalPlaceAggregatesResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    read_model: str = Field(min_length=1, max_length=64)
    read_model_version: str = Field(min_length=1, max_length=32)
    source: Literal["governed_review_mention_aggregation"] = "governed_review_mention_aggregation"
    provider_class: Literal["aggregated_review_mentions"] = "aggregated_review_mentions"
    # Honest availability: flag-off governance returns an empty, explicitly
    # unavailable result instead of an error or fabricated rows.
    available: bool
    items: list[LocalSignalPlaceAggregate] = Field(default_factory=list, max_length=50)
    computed_at: datetime | None = None
    last_refreshed_at: datetime | None = None
