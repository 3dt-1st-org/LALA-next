from __future__ import annotations

import json

from apps.api.app.tools import enrich_place_ai_columns


def test_place_ai_enrichment_plan_uses_data_dictionary_names(capsys):
    exit_code = enrich_place_ai_columns.main(["--json"])

    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["target"] == "travel.places"
    assert "region_name_en" in payload["enriched_columns"]
    assert "travel.place_enrichments" in payload["enriched_columns"]
    assert payload["live_ai_call"] is False
    assert payload["db_mutation"] is False


def test_parse_ai_response_accepts_region_name_en_and_legacy_alias():
    candidates = [
        enrich_place_ai_columns.PlaceCandidate(
            place_id="place-1",
            name_ko="수원화성",
            category="attraction",
            region_name_ko="수원시",
        ),
        enrich_place_ai_columns.PlaceCandidate(
            place_id="place-2",
            name_ko="팔달문 맛집",
            category="restaurant",
            region_name_ko="수원시",
        ),
    ]
    raw = json.dumps(
        {
            "results": [
                {
                    "place_id": "place-1",
                    "name_en": "Suwon Hwaseong Fortress",
                    "region_name_en": "Suwon-si",
                    "is_indoor": False,
                    "confidence": 0.91,
                },
                {
                    "place_id": "place-2",
                    "name_en": "Paldalmun Restaurant",
                    "region_en": "Suwon-si",
                    "is_indoor": None,
                },
            ]
        },
        ensure_ascii=False,
    )

    parsed = enrich_place_ai_columns.parse_ai_response(raw, candidates)

    assert parsed[0].place_id == "place-1"
    assert parsed[0].region_name_en == "Suwon-si"
    assert parsed[0].is_indoor is False
    assert parsed[0].confidence == 0.91
    assert parsed[1].region_name_en == "Suwon-si"
