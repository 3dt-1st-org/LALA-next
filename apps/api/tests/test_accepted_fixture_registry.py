from __future__ import annotations

import json

import pytest

from apps.api.app.services import accepted_fixture_registry as fixtures


@pytest.fixture(autouse=True)
def _isolated_registry():
    fixtures.clear_accepted_fixture_registry()
    yield
    fixtures.clear_accepted_fixture_registry()


def test_registered_synthetic_fixture_resolves_with_test_only_provenance():
    fixture = fixtures.register_accepted_fixture(
        "tour:synthetic-place",
        payload={"contentid": "tour-1", "title": "Synthetic Place"},
        description="synthetic tour_api place used by adapter tests",
    )
    assert fixture.fixture_id == "tour:synthetic-place"
    assert fixture.provenance.origin == "synthetic"
    assert fixture.provenance.approval_status == "approved"
    assert fixture.provenance.intended_use == "test_only"
    assert fixtures.is_accepted_fixture("tour:synthetic-place") is True
    assert fixtures.resolve_accepted_fixture_payload("tour:synthetic-place") == {
        "contentid": "tour-1",
        "title": "Synthetic Place",
    }


def test_unregistered_fixture_fails_closed_everywhere():
    assert fixtures.is_accepted_fixture("ghost") is False
    with pytest.raises(fixtures.AcceptedFixtureRegistryError, match="not registered"):
        fixtures.get_accepted_fixture("ghost")
    with pytest.raises(fixtures.AcceptedFixtureRegistryError, match="not registered"):
        fixtures.resolve_accepted_fixture_payload("ghost")
    with pytest.raises(fixtures.AcceptedFixtureRegistryError, match="not registered"):
        fixtures.assert_fixture_accepted("ghost")


@pytest.mark.parametrize(
    ("fixture_id", "payload"),
    [
        ("bad:secret-scalar", {"reference": "sk-abcd1234efgh"}),  # pragma: allowlist secret
        ("bad:bearer", {"header": "Bearer abc.def.ghi"}),  # pragma: allowlist secret
        ("bad:dsn", {"connection": "postgres://u:p@h/db"}),  # pragma: allowlist secret
        ("bad:aws", {"snapshot": "AKIAIOSFODNN7EXAMPLE0000"}),  # pragma: allowlist secret
    ],
)
def test_secret_shaped_payloads_are_rejected_as_not_synthetic(fixture_id, payload):
    with pytest.raises(fixtures.AcceptedFixtureRegistryError, match="secret-shaped"):
        fixtures.register_accepted_fixture(fixture_id, payload=payload, description="x")
    assert fixtures.is_accepted_fixture(fixture_id) is False


@pytest.mark.parametrize(
    ("fixture_id", "payload"),
    [
        ("bad:review", {"review_body": "a real captured review"}),
        ("bad:author", {"author_name": "real person"}),
        ("bad:email", {"customer_email": "real@example.com"}),
        ("bad:provider", {"provider_payload": {"raw": "upstream"}}),
    ],
)
def test_non_synthetic_identity_and_review_fields_are_rejected(fixture_id, payload):
    with pytest.raises(fixtures.AcceptedFixtureRegistryError, match="forbidden field"):
        fixtures.register_accepted_fixture(fixture_id, payload=payload, description="x")
    assert fixtures.is_accepted_fixture(fixture_id) is False


def test_secret_nested_deep_inside_payload_is_rejected():
    with pytest.raises(fixtures.AcceptedFixtureRegistryError, match="secret-shaped"):
        fixtures.register_accepted_fixture(
            "bad:nested",
            payload={"rows": [{"v": "sk-deep1234secret"}]},  # pragma: allowlist secret
            description="x",
        )


def test_registration_is_idempotent_for_identical_payload_but_rejects_drift():
    payload = {"contentid": "tour-1", "title": "Synthetic Place"}
    first = fixtures.register_accepted_fixture(
        "tour:place", payload=payload, description="synthetic place"
    )
    second = fixtures.register_accepted_fixture(
        "tour:place", payload=payload, description="synthetic place"
    )
    assert first is second
    with pytest.raises(fixtures.AcceptedFixtureRegistryError, match="different payload"):
        fixtures.register_accepted_fixture(
            "tour:place",
            payload={"contentid": "tour-1", "title": "Tampered Title"},
            description="synthetic place",
        )


def test_resolve_returns_a_copy_so_callers_cannot_mutate_the_registry_contract():
    fixtures.register_accepted_fixture(
        "tour:place", payload={"contentid": "tour-1"}, description="synthetic"
    )
    resolved = fixtures.resolve_accepted_fixture_payload("tour:place")
    resolved["contentid"] = "tampered"
    assert fixtures.resolve_accepted_fixture_payload("tour:place") == {"contentid": "tour-1"}


def test_post_registration_caller_mutation_does_not_change_stored_payload():
    payload = {"contentid": "tour-1", "tags": ["a"]}
    fixtures.register_accepted_fixture("tour:place", payload=payload, description="synthetic")
    payload["contentid"] = "mutated"
    payload["tags"].append("b")
    assert fixtures.resolve_accepted_fixture_payload("tour:place") == {
        "contentid": "tour-1",
        "tags": ["a"],
    }


def test_invalid_fixture_ids_and_empty_descriptions_are_rejected():
    with pytest.raises(fixtures.AcceptedFixtureRegistryError, match="id must not be empty"):
        fixtures.register_accepted_fixture("   ", payload={}, description="x")
    with pytest.raises(fixtures.AcceptedFixtureRegistryError, match="bounded opaque"):
        fixtures.register_accepted_fixture("bad id with space", payload={}, description="x")
    with pytest.raises(fixtures.AcceptedFixtureRegistryError, match="non-empty provenance"):
        fixtures.register_accepted_fixture("tour:place", payload={}, description="   ")


def test_list_accepted_fixtures_is_ordered_and_complete():
    fixtures.register_accepted_fixture("zeta", payload={"v": 1}, description="z")
    fixtures.register_accepted_fixture("alpha", payload={"v": 1}, description="a")
    listed = fixtures.list_accepted_fixtures()
    assert [item.fixture_id for item in listed] == ["alpha", "zeta"]


def test_public_payload_contains_no_secret_review_or_author_text():
    fixtures.register_accepted_fixture(
        "tour:place",
        payload={"contentid": "tour-1", "title": "Synthetic Place"},
        description="synthetic tour_api place",
    )
    fixture = fixtures.get_accepted_fixture("tour:place")
    serialized = json.dumps(fixture, default=str, ensure_ascii=False).lower()
    for forbidden in ("sk-", "bearer", "postgresql://", "review", "author", "password"):
        assert forbidden not in serialized
