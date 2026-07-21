from __future__ import annotations

import json
import sys
from types import SimpleNamespace

from apps.api.app.services import tour_api_ingest
from apps.api.app.tools import run_tour_api_ingest


def test_tour_api_ingest_plan_uses_public_data_key_without_live_call(capsys):
    exit_code = run_tour_api_ingest.main(["--json"])

    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["ok"] is True
    assert payload["mode"] == "plan"
    assert payload["source_name"] == "tour_api"
    assert payload["operation"] == "areaBasedList2"
    assert payload["image_operation"] == "detailImage2"
    assert payload["target"] == "travel.places"
    assert payload["required_env"] == ["PUBLIC_DATA_SERVICE_KEY"]
    assert payload["live_api_call"] is False
    assert payload["db_mutation"] is False


def test_tour_api_ingest_plan_supports_all_supported_areas(capsys):
    exit_code = run_tour_api_ingest.main(["--json", "--all-supported-areas"])

    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["area_code"] == "multi"
    assert len(payload["area_codes"]) == 17
    assert payload["area_codes"][0] == "1"
    assert payload["area_codes"][-1] == "39"


def test_parse_tour_api_place_maps_fields_to_data_dictionary_names():
    item = {
        "contentid": "2874056",
        "contenttypeid": "12",
        "title": "포천아트밸리",
        "addr1": "경기도 포천시 신북면 아트밸리로 234",
        "addr2": "",
        "areacode": "31",
        "sigungucode": "29",
        "mapx": "127.236",
        "mapy": "37.923",
        "firstimage": "http://tong.visitkorea.or.kr/cms/resource/image.jpg",
        "modifiedtime": "20260601010101",
    }

    place = tour_api_ingest.parse_tour_api_place(item)

    assert place is not None
    assert place.place_id == "tour-api-2874056"
    assert place.category == "attraction"
    assert place.region_name_ko == "포천시"
    assert place.to_place_row() == {
        "place_id": "tour-api-2874056",
        "name_ko": "포천아트밸리",
        "category": "attraction",
        "address_ko": "경기도 포천시 신북면 아트밸리로 234",
        "image_url": "https://tong.visitkorea.or.kr/cms/resource/image.jpg",
        "region_name_ko": "포천시",
        "province_code": "31",
        "city_code": "29",
        "lat": 37.923,
        "lng": 127.236,
        "primary_source": "tour_api",
        "source_record_id": "2874056",
    }


def test_infer_region_name_accepts_seoul_short_alias():
    assert tour_api_ingest.infer_region_name_ko("서울시 종로구 익선동") == "종로구"


def test_infer_region_name_accepts_busan_province_alias():
    assert tour_api_ingest.infer_region_name_ko("부산광역시 해운대구 우동") == "해운대구"


def test_fetch_result_dedupes_content_ids(monkeypatch):
    class Response:
        def __init__(self, payload):
            self._payload = payload

        def raise_for_status(self):
            return None

        def json(self):
            return self._payload

    list_payload = {
        "response": {
            "header": {"resultCode": "0000", "resultMsg": "OK"},
            "body": {
                "items": {
                    "item": [
                        {
                            "contentid": "1",
                            "contenttypeid": "12",
                            "title": "장소",
                            "addr1": "경기도 수원시 팔달구",
                            "areacode": "31",
                            "sigungucode": "13",
                            "mapx": "127.0",
                            "mapy": "37.0",
                        },
                        {
                            "contentid": "1",
                            "contenttypeid": "12",
                            "title": "장소",
                            "addr1": "경기도 수원시 팔달구",
                            "areacode": "31",
                            "sigungucode": "13",
                            "mapx": "127.0",
                            "mapy": "37.0",
                        },
                    ]
                }
            },
        }
    }
    detail_payload = {
        "response": {
            "header": {"resultCode": "0000", "resultMsg": "OK"},
            "body": {
                "items": {
                    "item": {
                        "contentid": "1",
                        "originimgurl": "https://example.invalid/detail.jpg",
                    }
                }
            },
        }
    }

    calls = []

    def get(url, params, timeout):
        calls.append({"url": url, "params": params, "timeout": timeout})
        if url.endswith("/detailImage2"):
            return Response(detail_payload)
        return Response(list_payload)

    monkeypatch.setitem(sys.modules, "requests", SimpleNamespace(get=get))

    result = tour_api_ingest.fetch_tour_api_places(
        service_key="secret-key",
        content_type_ids=("12",),
        rows=2,
        page_size=2,
    )

    assert len(calls) == 2
    assert calls[0]["url"].endswith("/areaBasedList2")
    assert calls[0]["params"]["serviceKey"] == "secret-key"
    assert calls[1]["url"].endswith("/detailImage2")
    assert calls[1]["params"]["contentId"] == "1"
    assert result.request_count == 1
    assert result.image_request_count == 1
    assert result.image_error_count == 0
    assert result.raw_count == 2
    assert len(result.places) == 1
    assert result.places[0].first_image == "https://example.invalid/detail.jpg"


def test_fetch_result_can_sweep_multiple_area_codes(monkeypatch):
    calls = []

    def fake_fetch(**kwargs):
        calls.append(kwargs["area_code"])
        return tour_api_ingest.TourApiFetchResult(
            places=(
                tour_api_ingest.TourApiPlace(
                    content_id=f"{kwargs['area_code']}-1",
                    content_type_id="12",
                    title=f"장소-{kwargs['area_code']}",
                    category="attraction",
                    addr1="부산광역시 해운대구",
                    addr2=None,
                    area_code=kwargs["area_code"],
                    sigungu_code="1",
                    lat=35.1,
                    lng=129.1,
                    first_image=None,
                    modified_time=None,
                ),
            ),
            request_count=1,
            image_request_count=0,
            image_error_count=0,
            raw_count=1,
            area_code=kwargs["area_code"],
            area_codes=(kwargs["area_code"],),
            content_type_ids=("12",),
        )

    monkeypatch.setattr(tour_api_ingest, "fetch_tour_api_places", fake_fetch)

    result = tour_api_ingest.fetch_tour_api_places_for_area_codes(
        service_key="secret-key",
        area_codes=("1", "6"),
        content_type_ids=("12",),
        rows=1,
        page_size=1,
    )

    assert calls == ["1", "6"]
    assert result.area_code == "multi"
    assert result.area_codes == ("1", "6")
    assert result.request_count == 2
    assert result.raw_count == 2
    assert len(result.places) == 2


def test_fetch_result_skips_detail_image_when_firstimage_exists(monkeypatch):
    class Response:
        def raise_for_status(self):
            return None

        def json(self):
            return {
                "response": {
                    "header": {"resultCode": "0000", "resultMsg": "OK"},
                    "body": {
                        "items": {
                            "item": [
                                {
                                    "contentid": "1",
                                    "contenttypeid": "12",
                                    "title": "장소",
                                    "addr1": "경기도 수원시 팔달구",
                                    "areacode": "31",
                                    "sigungucode": "13",
                                    "mapx": "127.0",
                                    "mapy": "37.0",
                                    "firstimage": "http://tong.visitkorea.or.kr/cms/resource/list.jpg",
                                },
                            ]
                        }
                    },
                }
            }

    calls = []

    def get(url, params, timeout):
        calls.append({"url": url, "params": params, "timeout": timeout})
        return Response()

    monkeypatch.setitem(sys.modules, "requests", SimpleNamespace(get=get))

    result = tour_api_ingest.fetch_tour_api_places(
        service_key="secret-key",
        content_type_ids=("12",),
        rows=1,
        page_size=1,
    )

    assert len(calls) == 1
    assert calls[0]["url"].endswith("/areaBasedList2")
    assert result.image_request_count == 0
    assert result.image_error_count == 0
    assert result.raw_count == 1
    assert len(result.places) == 1
    assert result.places[0].first_image == "https://tong.visitkorea.or.kr/cms/resource/list.jpg"


def test_fetch_result_can_skip_missing_detail_image_lookup(monkeypatch):
    class Response:
        def raise_for_status(self):
            return None

        def json(self):
            return {
                "response": {
                    "header": {"resultCode": "0000", "resultMsg": "OK"},
                    "body": {
                        "items": {
                            "item": {
                                "contentid": "1",
                                "contenttypeid": "12",
                                "title": "장소",
                                "addr1": "경기도 수원시 팔달구",
                                "areacode": "31",
                                "sigungucode": "13",
                                "mapx": "127.0",
                                "mapy": "37.0",
                            }
                        }
                    },
                }
            }

    calls = []

    def get(url, params, timeout):
        calls.append({"url": url, "params": params, "timeout": timeout})
        return Response()

    monkeypatch.setitem(sys.modules, "requests", SimpleNamespace(get=get))

    result = tour_api_ingest.fetch_tour_api_places(
        service_key="secret-key",
        content_type_ids=("12",),
        rows=1,
        page_size=1,
        fetch_missing_images=False,
    )

    assert len(calls) == 1
    assert calls[0]["url"].endswith("/areaBasedList2")
    assert result.image_request_count == 0
    assert result.image_error_count == 0
    assert len(result.places) == 1
    assert result.places[0].first_image is None


def test_fetch_result_keeps_place_when_detail_image_lookup_fails(monkeypatch):
    class Response:
        def raise_for_status(self):
            return None

        def json(self):
            return {
                "response": {
                    "header": {"resultCode": "0000", "resultMsg": "OK"},
                    "body": {
                        "items": {
                            "item": {
                                "contentid": "1",
                                "contenttypeid": "12",
                                "title": "장소",
                                "addr1": "경기도 수원시 팔달구",
                                "areacode": "31",
                                "sigungucode": "13",
                                "mapx": "127.0",
                                "mapy": "37.0",
                            }
                        }
                    },
                }
            }

    calls = []

    def get(url, params, timeout):
        calls.append({"url": url, "params": params, "timeout": timeout})
        if url.endswith("/detailImage2"):
            raise RuntimeError("detail image unavailable")
        return Response()

    monkeypatch.setitem(sys.modules, "requests", SimpleNamespace(get=get))

    result = tour_api_ingest.fetch_tour_api_places(
        service_key="secret-key",
        content_type_ids=("12",),
        rows=1,
        page_size=1,
    )

    assert len(calls) == 2
    assert result.image_request_count == 1
    assert result.image_error_count == 1
    assert len(result.places) == 1
    assert result.places[0].first_image is None


def test_apply_requires_guard_before_reading_db(monkeypatch, capsys):
    password = "example" + "-password"
    dsn = "postgresql://user:" + password + "@example.postgres.database.azure.com/db"
    monkeypatch.setenv("PUBLIC_DATA_SERVICE_KEY", "public-data-secret")
    monkeypatch.setenv("DB_DSN", dsn)
    monkeypatch.delenv(run_tour_api_ingest.ALLOW_ENV, raising=False)

    exit_code = run_tour_api_ingest.main(["--apply", "--confirm", run_tour_api_ingest.CONFIRM_TEXT])

    output = capsys.readouterr().out
    assert exit_code == 2
    assert run_tour_api_ingest.ALLOW_ENV in output
    assert dsn not in output
    assert password not in output
    assert "public-data-secret" not in output


def test_preview_redacts_service_key_on_execution_error(monkeypatch, capsys):
    monkeypatch.setenv("PUBLIC_DATA_SERVICE_KEY", "public-data-secret")

    def fail(**kwargs):
        raise RuntimeError("bad service key public-data-secret")

    monkeypatch.setattr(run_tour_api_ingest, "fetch_tour_api_places", fail)

    exit_code = run_tour_api_ingest.main(["--preview"])

    output = capsys.readouterr().out
    assert exit_code == 2
    assert "[redacted]" in output
    assert "public-data-secret" not in output


def test_upsert_tour_api_places_targets_source_files_and_places(monkeypatch):
    executed = []

    class Cursor:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def execute(self, sql, params=None):
            executed.append((sql, params))
            self.rowcount = 1

        def fetchone(self):
            return ("source-file-id",)

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
    result = tour_api_ingest.TourApiFetchResult(
        places=(
            tour_api_ingest.TourApiPlace(
                content_id="1",
                content_type_id="12",
                title="장소",
                category="attraction",
                addr1="경기도 수원시 팔달구",
                addr2=None,
                area_code="31",
                sigungu_code="13",
                lat=37.0,
                lng=127.0,
                first_image=None,
                modified_time=None,
            ),
        ),
        request_count=1,
        image_request_count=0,
        image_error_count=0,
        raw_count=1,
        area_code="31",
        area_codes=("31",),
        content_type_ids=("12",),
    )

    payload = tour_api_ingest.upsert_tour_api_places(
        dsn="postgresql://redacted",
        result=result,
        connect_timeout=7,
    )

    assert payload["upserted_rows"] == 1
    assert "INSERT INTO ingest.source_files" in executed[1][0]
    assert "INSERT INTO travel.places" in executed[2][0]
    assert "COALESCE(EXCLUDED.image_url, travel.places.image_url)" in executed[2][0]
    assert executed[-1] == ("commit", None)
