from __future__ import annotations

from apps.api.app.services import i18n_catalog

UPSTREAM_SOURCE_LABELS_KO: dict[str, str] = i18n_catalog.source_labels_by_locale(
    namespace="organization",
    language="ko",
)

UPSTREAM_SOURCE_LABELS_EN: dict[str, str] = i18n_catalog.source_labels_by_locale(
    namespace="evidence",
    language="en",
)


def source_evidence_label(source: str | None, *, language: str = "ko") -> str | None:
    return i18n_catalog.source_label(source, language=language, namespace="evidence")


def source_organization_label(source: str | None, *, language: str = "ko") -> str | None:
    return i18n_catalog.source_label(source, language=language, namespace="organization")
