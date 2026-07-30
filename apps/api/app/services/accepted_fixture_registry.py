"""Accepted-fixture registry for test-only synthetic source fixtures.

Tracks the synthetic payloads that tests are permitted to claim through the
official-source contract. Every accepted fixture carries explicit provenance
(origin = ``synthetic``, approval = ``approved``, intended use =
``test_only``). A fixture that is not registered can never be resolved, so the
normal/test-claim path fails closed instead of silently accepting an
unreviewed payload.

The registry is deliberately disjoint from any live data path. It performs no
network, DB, apply, seed, crawl, AI/TTS, or secret access. It rejects
non-synthetic values -- secret-shaped strings, raw-review/author/credential
fields -- so a real captured value can never be smuggled in as an "accepted
fixture".
"""

from __future__ import annotations

import copy
import re
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any, Final, Literal

FixtureOrigin = Literal["synthetic"]
FixtureApprovalStatus = Literal["approved"]
FixtureIntendedUse = Literal["test_only"]

# Secret-shaped values that must never appear in a synthetic fixture. Matches
# the upstream adapter chokepoints (service keys, bearer tokens, DSNs) so a
# real credential can never be registered as an accepted fixture.
_SECRET_SHAPED_VALUE: Final[re.Pattern[str]] = re.compile(
    r"(?:sk-[A-Za-z0-9_-]{8,}|Bearer\s+\S+|postgres(?:ql)?://|AKIA[0-9A-Z]{12,})",
    re.IGNORECASE,
)

# Field/name terms that signal non-synthetic or identity-sensitive content.
# Mirrors the adapters' forbidden-field intent: raw review bodies, authors,
# credentials, provider payloads, and RAG-shaped fields are not synthetic
# fixture material.
_FORBIDDEN_FIXTURE_TERMS: Final[tuple[str, ...]] = (
    "author",
    "email",
    "phone",
    "review",
    "raw",
    "token",
    "secret",
    "password",
    "bearer",
    "apikey",
    "api_key",
    "embedding",
    "vector",
    "prompt",
    "completion",
    "citation",
    "private",
    "provider_payload",
    "body",
)


class AcceptedFixtureRegistryError(ValueError):
    """Raised when a fixture is rejected or resolved fail-closed."""


@dataclass(frozen=True)
class FixtureProvenance:
    """Provenance record proving a fixture is synthetic and test-only."""

    origin: FixtureOrigin
    approval_status: FixtureApprovalStatus
    intended_use: FixtureIntendedUse
    description: str


@dataclass(frozen=True)
class AcceptedFixture:
    """One registered synthetic fixture and its provenance."""

    fixture_id: str
    payload: Any
    provenance: FixtureProvenance


_REGISTRY: Final[dict[str, AcceptedFixture]] = {}


def register_accepted_fixture(
    fixture_id: str,
    *,
    payload: Any,
    description: str,
) -> AcceptedFixture:
    """Register one synthetic fixture with explicit test-only provenance.

    The payload is validated to be synthetic-safe (no secret-shaped values, no
    raw-review/author/credential fields) and deep-copied so later caller
    mutations cannot change the registered contract. Registration is idempotent
    for an identical payload; re-registering the same id with a different
    payload is rejected so a fixture id cannot silently switch meanings.
    """
    canonical_id = _canonical_id(fixture_id)
    text = description.strip()
    if not text:
        raise AcceptedFixtureRegistryError(
            "An accepted fixture requires a non-empty provenance description."
        )
    _assert_synthetic_payload(canonical_id, payload)
    provenance = FixtureProvenance(
        origin="synthetic",
        approval_status="approved",
        intended_use="test_only",
        description=text,
    )
    frozen_payload = copy.deepcopy(payload)
    existing = _REGISTRY.get(canonical_id)
    if existing is not None:
        if not _payloads_equal(existing.payload, frozen_payload):
            raise AcceptedFixtureRegistryError(
                f"Fixture {canonical_id!r} is already registered with a different payload."
            )
        return existing
    fixture = AcceptedFixture(
        fixture_id=canonical_id,
        payload=frozen_payload,
        provenance=provenance,
    )
    _REGISTRY[canonical_id] = fixture
    return fixture


def register_accepted_fixtures(
    fixtures: Mapping[str, tuple[Any, str]],
) -> tuple[AcceptedFixture, ...]:
    """Register many fixtures from an id -> (payload, description) mapping."""
    registered: list[AcceptedFixture] = []
    for fixture_id, (payload, description) in fixtures.items():
        registered.append(
            register_accepted_fixture(fixture_id, payload=payload, description=description)
        )
    return tuple(registered)


def get_accepted_fixture(fixture_id: str) -> AcceptedFixture:
    """Return the registered fixture or raise (fail-closed)."""
    canonical_id = _canonical_id(fixture_id)
    fixture = _REGISTRY.get(canonical_id)
    if fixture is None:
        raise AcceptedFixtureRegistryError(
            f"Fixture {canonical_id!r} is not registered as an accepted fixture."
        )
    return fixture


def resolve_accepted_fixture_payload(fixture_id: str) -> Any:
    """Return a deep copy of the registered fixture payload.

    A deep copy is returned so the registry's stored contract cannot be mutated
    by callers. Unregistered ids raise, which is the fail-closed gate for any
    normal/test-claim path that consumes accepted fixtures.
    """
    return copy.deepcopy(get_accepted_fixture(fixture_id).payload)


def is_accepted_fixture(fixture_id: str) -> bool:
    """Return ``True`` only if ``fixture_id`` is a registered accepted fixture."""
    return _canonical_id(fixture_id) in _REGISTRY


def assert_fixture_accepted(fixture_id: str) -> AcceptedFixture:
    """Fail closed unless ``fixture_id`` is a registered accepted fixture."""
    return get_accepted_fixture(fixture_id)


def list_accepted_fixtures() -> tuple[AcceptedFixture, ...]:
    """Return a snapshot of every registered accepted fixture, by id order."""
    return tuple(_REGISTRY[key] for key in sorted(_REGISTRY))


def clear_accepted_fixture_registry() -> None:
    """Clear the registry.

    Provided for test isolation so one test's fixtures cannot leak into another
    test's fail-closed assertion. Production code must not call this.
    """
    _REGISTRY.clear()


def _canonical_id(fixture_id: object) -> str:
    text = " ".join(str(fixture_id or "").strip().split())
    if not text:
        raise AcceptedFixtureRegistryError("An accepted fixture id must not be empty.")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9:._-]{0,127}", text):
        raise AcceptedFixtureRegistryError(
            f"Fixture id must be a bounded opaque reference: {fixture_id!r}."
        )
    return text


def _assert_synthetic_payload(fixture_id: str, payload: Any) -> None:
    """Reject any payload that looks non-synthetic (secrets, raw review, PII)."""
    seen: set[int] = set()
    _walk_synthetic(fixture_id, "", payload, seen)


def _walk_synthetic(fixture_id: str, path: str, value: Any, seen: set[int]) -> None:
    if id(value) in seen:
        return
    seen.add(id(value))
    if isinstance(value, str):
        if _SECRET_SHAPED_VALUE.search(value):
            raise AcceptedFixtureRegistryError(
                f"Fixture {fixture_id!r} payload at {path or '<root>'!r} contains a "
                "secret-shaped value and is not synthetic."
            )
        return
    if isinstance(value, Mapping):
        _check_mapping(fixture_id, path, list(value.items()), seen)
        return
    if isinstance(value, (list, tuple, set, frozenset)):
        for index, item in enumerate(value):
            _walk_synthetic(fixture_id, f"{path}[{index}]" if path else f"[{index}]", item, seen)
        return
    # Scalars (int/float/bool/None/Decimal/...) carry no field name and no
    # string text to inspect; they are accepted as synthetic primitives.
    return


def _check_mapping(
    fixture_id: str,
    path: str,
    items: list[tuple[Any, Any]],
    seen: set[int],
) -> None:
    for key, val in items:
        key_text = str(key).strip().lower()
        child_path = f"{path}.{key}" if path else str(key)
        if any(term in key_text.replace(" ", "_") for term in _FORBIDDEN_FIXTURE_TERMS):
            raise AcceptedFixtureRegistryError(
                f"Fixture {fixture_id!r} uses a forbidden field {key!r} at "
                f"{child_path!r}; synthetic fixtures must not carry raw review, "
                "author, credential, or provider-payload fields."
            )
        _walk_synthetic(fixture_id, child_path, val, seen)


def _payloads_equal(left: Any, right: Any) -> bool:
    return left == right


__all__ = [
    "AcceptedFixture",
    "AcceptedFixtureRegistryError",
    "FixtureApprovalStatus",
    "FixtureIntendedUse",
    "FixtureOrigin",
    "FixtureProvenance",
    "assert_fixture_accepted",
    "clear_accepted_fixture_registry",
    "get_accepted_fixture",
    "is_accepted_fixture",
    "list_accepted_fixtures",
    "register_accepted_fixture",
    "register_accepted_fixtures",
    "resolve_accepted_fixture_payload",
]
