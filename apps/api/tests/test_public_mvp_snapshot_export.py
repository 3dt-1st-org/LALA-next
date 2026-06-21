from __future__ import annotations

import json
import sys
import types
from decimal import Decimal
from importlib.resources import files

from apps.api.app.services import public_mvp_snapshot
from apps.api.app.tools import export_public_mvp_snapshot


def _db_rows() -> list[dict]:
    return [
        {
            "place_id": "tour-api-129765",
            "name_ko": "호암미술관",
            "name_en": "Ho-Am Art Museum",
            "category": "culture_venue",
            "lat": Decimal("37.293314781"),
            "lng": Decimal("127.1923454131"),
            "address_ko": "경기도 용인시 처인구 포곡읍 에버랜드로562번길 38",
            "address_en": "38 Everland-ro 562beon-gil, Yongin-si, Gyeonggi-do",
            "image_url": "https://example.test/hoam.jpg",
            "region_ko": "용인시",
            "region_en": "Yongin",
            "event_start_date": None,
            "event_end_date": None,
            "event_url": None,
            "is_ongoing": None,
            "is_approximate_location": False,
            "upstream_source": "tour_api",
            "local_spending_score": None,
            "small_merchant_fit_score": Decimal("0.7600"),
            "demand_dispersion_score": Decimal("0.9500"),
            "culture_relevance_score": Decimal("0.7000"),
            "weather_fit_score": None,
            "review_quality_score": None,
            "accessibility_fit_score": Decimal("0.6200"),
            "final_score": Decimal("0.8562"),
            "formula_version": "local-value-v2",
            "score_features": {
                "primary_source": "tour_api",
                "missing_signals": ["review_attribute_analysis"],
            },
        }
    ]


def test_build_snapshot_payload_marks_public_mvp_basis() -> None:
    payload = public_mvp_snapshot.build_snapshot_payload(
        _db_rows(),
        snapshot_id="test-snapshot",
        lat=37.2636,
        lng=127.0286,
        radius_m=50000,
        category="all",
    )

    encoded = public_mvp_snapshot.payload_to_json(payload)
    decoded = json.loads(encoded)
    place = decoded["places"][0]

    assert decoded["snapshot_id"] == "test-snapshot"
    assert decoded["query"]["radius_m"] == 50000
    assert place["place_id"] == "tour-api-129765"
    assert place["image_url"] == "https://example.test/hoam.jpg"
    assert place["event_start_date"] is None
    assert place["event_url"] is None
    assert place["is_ongoing"] is None
    assert place["is_approximate_location"] is False
    assert place["upstream_source"] == "tour_api"
    assert place["score"]["data_basis"] == "public_mvp_snapshot"
    assert place["score"]["final_score"] == 0.8562
    assert place["score"]["components"]["small_merchant_fit_score"] == 0.76
    assert place["score"]["components"]["accessibility_fit_score"] == 0.62
    assert place["score"]["features"]["snapshot_source"] == "analytics.place_score_snapshots"


def test_build_snapshot_payload_preserves_gyeonggi_in_english_address() -> None:
    rows = _db_rows()
    rows[0]["address_en"] = "38 Everland-ro 562beon-gil, Pogok-eup, Cheoin-gu, Yongin-si"

    payload = public_mvp_snapshot.build_snapshot_payload(
        rows,
        snapshot_id="test-address",
        lat=37.2636,
        lng=127.0286,
        radius_m=50000,
        category="all",
    )

    assert payload["places"][0]["address_en"].endswith(", Gyeonggi-do")


def test_build_snapshot_payload_upgrades_tour_api_images_to_https() -> None:
    rows = _db_rows()
    rows[0]["image_url"] = "http://tong.visitkorea.or.kr/cms/resource/photo.jpg"

    payload = public_mvp_snapshot.build_snapshot_payload(
        rows,
        snapshot_id="test-image-url",
        lat=37.2636,
        lng=127.0286,
        radius_m=50000,
        category="all",
    )

    assert (
        payload["places"][0]["image_url"]
        == "https://tong.visitkorea.or.kr/cms/resource/photo.jpg"
    )


def test_build_snapshot_payload_fills_gyeonggi_region_english_name() -> None:
    rows = _db_rows()
    rows[0]["region_en"] = None

    payload = public_mvp_snapshot.build_snapshot_payload(
        rows,
        snapshot_id="test-region",
        lat=37.2636,
        lng=127.0286,
        radius_m=50000,
        category="all",
    )

    assert payload["places"][0]["region_en"] == "Yongin-si"


def test_build_snapshot_payload_fills_seoul_region_english_name() -> None:
    rows = _db_rows()
    rows[0]["address_ko"] = "서울특별시 종로구 세종대로 172"
    rows[0]["address_en"] = "Sejong-daero 172"
    rows[0]["region_ko"] = "종로구"
    rows[0]["region_en"] = None

    payload = public_mvp_snapshot.build_snapshot_payload(
        rows,
        snapshot_id="test-seoul-region",
        lat=37.5665,
        lng=126.9780,
        radius_m=50000,
        category="all",
    )

    assert payload["places"][0]["address_en"].endswith(", Seoul")
    assert payload["places"][0]["region_en"] == "Jongno-gu"


def test_bundled_snapshot_covers_supported_regions() -> None:
    payload = json.loads(
        files("apps.api.app.data").joinpath("public_mvp_places.json").read_text(encoding="utf-8")
    )
    regions = {row.get("region_ko") for row in payload["places"]}

    assert regions == set(public_mvp_snapshot.DEFAULT_REGION_NAME_EN)


def test_bundled_snapshot_uses_https_tour_api_images() -> None:
    payload = json.loads(
        files("apps.api.app.data").joinpath("public_mvp_places.json").read_text(encoding="utf-8")
    )
    image_urls = [row.get("image_url") for row in payload["places"] if row.get("image_url")]

    assert image_urls
    assert not any(url.startswith("http://tong.visitkorea.or.kr/") for url in image_urls)
    assert any(url.startswith("https://tong.visitkorea.or.kr/") for url in image_urls)


def test_fetch_snapshot_places_uses_schema_compatible_score_projection(monkeypatch) -> None:
    captured = {}

    class FakeCursor:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def execute(self, sql, params):
            captured["sql"] = sql
            captured["params"] = params

        def fetchall(self):
            return _db_rows()

    class FakeConnection:
        def cursor(self, cursor_factory=None):
            captured["cursor_factory"] = cursor_factory
            return FakeCursor()

        def close(self):
            return None

    psycopg2_module = types.ModuleType("psycopg2")
    psycopg2_module.connect = lambda dsn, connect_timeout: FakeConnection()
    extras_module = types.ModuleType("psycopg2.extras")
    extras_module.RealDictCursor = object()
    monkeypatch.setitem(sys.modules, "psycopg2", psycopg2_module)
    monkeypatch.setitem(sys.modules, "psycopg2.extras", extras_module)

    rows = public_mvp_snapshot.fetch_snapshot_places(
        dsn="postgresql://db.example/lala",
        lat=37.2636,
        lng=127.0286,
        radius_m=50000,
        category="all",
        limit=20,
        connect_timeout=3,
    )

    assert rows[0]["place_id"] == "tour-api-129765"
    assert "to_jsonb(score_snapshot)->>'small_merchant_fit_score'" in captured["sql"]
    assert "to_jsonb(score_snapshot)->>'accessibility_fit_score'" in captured["sql"]
    assert "NOT IN ('dev_seed', 'local_fixture')" in captured["sql"]
    assert "FLOOR(distance_m / 500.0) ASC" in captured["sql"]
    assert captured["params"][:6] == (37.2636, 127.0286, "all", "all", 50000, 20)


def test_export_plan_does_not_require_db(capsys) -> None:
    exit_code = export_public_mvp_snapshot.main(["--json"])

    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 0
    assert payload["mode"] == "plan"
    assert payload["db_mutation"] is False
    assert payload["file_write"] is False
    assert "travel.public_places" in payload["input_relations"]


def test_export_preview_redacts_dsn_on_error(monkeypatch, capsys) -> None:
    password = "snapshot" + "-password"
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    monkeypatch.setenv("DB_DSN", dsn)

    def fail(**kwargs):
        raise RuntimeError(f"failed for {dsn} password={password}")

    monkeypatch.setattr(public_mvp_snapshot, "fetch_snapshot_places", fail)

    exit_code = export_public_mvp_snapshot.main(["--preview"])

    output = capsys.readouterr().out
    assert exit_code == 2
    assert "[redacted]" in output
    assert dsn not in output
    assert password not in output


def test_export_write_requires_guard_before_reading_db(monkeypatch, tmp_path, capsys) -> None:
    monkeypatch.setenv("DB_DSN", "postgresql://user:password@example/db")
    monkeypatch.delenv(export_public_mvp_snapshot.ALLOW_ENV, raising=False)

    def fail_if_called(**kwargs):
        raise AssertionError("DB should not be read before write guard passes")

    monkeypatch.setattr(public_mvp_snapshot, "fetch_snapshot_places", fail_if_called)

    exit_code = export_public_mvp_snapshot.main(
        [
            "--write",
            "--confirm",
            export_public_mvp_snapshot.CONFIRM_TEXT,
            "--output",
            str(tmp_path / "snapshot.json"),
        ]
    )

    output = capsys.readouterr().out
    assert exit_code == 2
    assert export_public_mvp_snapshot.ALLOW_ENV in output


def test_export_write_creates_snapshot_file(monkeypatch, tmp_path, capsys) -> None:
    monkeypatch.setenv("DB_DSN", "postgresql://user:password@example/db")
    monkeypatch.setenv(export_public_mvp_snapshot.ALLOW_ENV, "1")
    monkeypatch.setattr(
        public_mvp_snapshot,
        "fetch_snapshot_places",
        lambda **kwargs: _db_rows(),
    )
    output_path = tmp_path / "public_mvp_places.json"

    exit_code = export_public_mvp_snapshot.main(
        [
            "--write",
            "--confirm",
            export_public_mvp_snapshot.CONFIRM_TEXT,
            "--output",
            str(output_path),
            "--snapshot-id",
            "test-write",
        ]
    )

    payload = json.loads(output_path.read_text(encoding="utf-8"))
    output = capsys.readouterr().out
    assert exit_code == 0
    assert "file_write=true" in output
    assert payload["snapshot_id"] == "test-write"
    assert payload["places"][0]["score"]["data_basis"] == "public_mvp_snapshot"
