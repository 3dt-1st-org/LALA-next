from __future__ import annotations

import json

from apps.api.app.services.franchise_identity import (
    FranchiseBrand,
    FranchiseLocation,
    PlaceBusinessCandidate,
    classify_place_business,
    normalize_business_name,
)
from apps.api.app.tools import run_franchise_identity_batch


def test_normalize_business_name_strips_branch_suffixes():
    assert normalize_business_name("무진장갈비 수원역점") == "무진장갈비"
    assert normalize_business_name("(주)라라푸드 강남점") == "라라푸드"


def test_classify_location_match_uses_coordinate_confidence():
    place = PlaceBusinessCandidate(
        place_id="restaurant-1",
        name_ko="라라버거 수원역점",
        category="restaurant",
        lat=37.2636,
        lng=127.0286,
    )
    brand = FranchiseBrand(
        brand_name_ko="라라버거",
        franchise_store_count=420,
        chain_scale_score=0.9,
    )
    location = FranchiseLocation(
        brand_name_ko="라라버거",
        store_name_ko="라라버거 수원역점",
        lat=37.2637,
        lng=127.0287,
    )

    identity = classify_place_business(place, brands=[brand], locations=[location])

    assert identity.business_identity_type == "national_franchise"
    assert identity.is_franchise is True
    assert identity.franchise_brand_name == "라라버거"
    assert identity.franchise_match_confidence == 0.95
    assert identity.small_merchant_fit_score == 0.34
    assert identity.features["match_type"] == "location_coordinate"


def test_classify_small_chain_keeps_positive_small_merchant_score():
    place = PlaceBusinessCandidate(
        place_id="restaurant-2",
        name_ko="동네국수 본점",
        category="restaurant",
    )
    brand = FranchiseBrand(
        brand_name_ko="동네국수",
        franchise_store_count=8,
        chain_scale_score=0.25,
    )

    identity = classify_place_business(place, brands=[brand])

    assert identity.business_identity_type == "local_small_chain"
    assert identity.small_merchant_fit_score == 0.76


def test_franchise_identity_batch_plan_has_no_mutation(capsys):
    exit_code = run_franchise_identity_batch.main(["--json"])

    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["db_mutation"] is False
    assert payload["target"] == "analytics.place_business_identity"
    assert "economy.franchise_brands" in payload["input_relations"]


def test_franchise_identity_apply_requires_guard(monkeypatch, capsys):
    monkeypatch.setenv("DB_DSN", "postgresql://user:secret@example.invalid/lala")
    monkeypatch.delenv(run_franchise_identity_batch.ALLOW_ENV, raising=False)

    exit_code = run_franchise_identity_batch.main(
        ["--apply", "--confirm", run_franchise_identity_batch.CONFIRM_TEXT]
    )

    output = capsys.readouterr().out
    assert exit_code == 2
    assert run_franchise_identity_batch.ALLOW_ENV in output
    assert "secret" not in output
