from __future__ import annotations

import json
import sys
from types import SimpleNamespace

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
    assert payload["retry_attempts"] == 3
    assert payload["live_ai_call"] is False
    assert payload["db_mutation"] is False


def test_place_ai_enrichment_english_only_plan_excludes_indoor(capsys):
    exit_code = enrich_place_ai_columns.main(["--json", "--fields", "english", "--replace-local"])

    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["fields"] == "english"
    assert payload["replace_local"] is True
    assert "name_en" in payload["enriched_columns"]
    assert "region_name_en" in payload["enriched_columns"]
    assert "is_indoor" not in payload["enriched_columns"]


def test_place_ai_enrichment_apply_requires_guard_before_settings(monkeypatch, capsys):
    monkeypatch.delenv(enrich_place_ai_columns.ALLOW_ENV, raising=False)

    def fail_if_called():
        raise AssertionError("settings should not be read before apply guard passes")

    monkeypatch.setattr(enrich_place_ai_columns, "get_settings", fail_if_called)

    exit_code = enrich_place_ai_columns.main(
        ["--apply", "--confirm", enrich_place_ai_columns.CONFIRM_TEXT]
    )

    output = capsys.readouterr().out
    assert exit_code == 2
    assert enrich_place_ai_columns.ALLOW_ENV in output


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


def test_ai_completion_retries_rate_limit(monkeypatch):
    calls = {"count": 0}

    class FakeCompletions:
        def create(self, **kwargs):
            calls["count"] += 1
            if calls["count"] == 1:
                raise RuntimeError("Too Many Requests")
            return SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content="{}"))])

    client = SimpleNamespace(chat=SimpleNamespace(completions=FakeCompletions()))
    monkeypatch.setattr(enrich_place_ai_columns.time, "sleep", lambda delay: None)

    response = enrich_place_ai_columns._create_chat_completion_with_retry(
        client=client,
        model="test-model",
        messages=[],
        retry_attempts=2,
        retry_delay_sec=0,
    )

    assert calls["count"] == 2
    assert response.choices[0].message.content == "{}"


def test_apply_english_only_replace_local_leaves_indoor_untouched(monkeypatch):
    executed = []

    class Cursor:
        rowcount = 1

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))

    class Connection:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def cursor(self):
            return Cursor()

        def commit(self):
            executed.append(("commit", None))

    def connect(dsn, connect_timeout):
        executed.append(("connect", {"dsn": dsn, "connect_timeout": connect_timeout}))
        return Connection()

    monkeypatch.setitem(sys.modules, "psycopg2", SimpleNamespace(connect=connect))
    monkeypatch.setattr(
        enrich_place_ai_columns,
        "get_settings",
        lambda: SimpleNamespace(azure_openai_deployment="test-model"),
    )

    updated = enrich_place_ai_columns.apply_enrichments(
        dsn="postgresql://redacted",
        enrichments=[
            enrich_place_ai_columns.PlaceEnrichment(
                place_id="tour-api-1",
                name_en="Natural English Name",
                address_en="Suwon-si, Gyeonggi-do",
                region_name_en="Suwon-si",
                is_indoor=True,
                confidence=0.9,
            )
        ],
        connect_timeout=3,
        fields="english",
        replace_local=True,
    )

    update_sql = next(sql for sql, _ in executed if "UPDATE travel.places" in sql)
    insert_params = next(
        params for sql, params in executed if "INSERT INTO travel.place_enrichments" in sql
    )
    assert updated == 1
    assert "UPDATE travel.places AS places" in update_sql
    assert "local_romanization" in update_sql
    assert "is_indoor =" not in update_sql
    assert insert_params["is_indoor"] is None
