from apps.api.app.services.naver_search_service import NaverSearchResult, _clean, _parse_date


def test_clean():
    assert _clean("<b>x</b>") == "x"


def test_date():
    assert _parse_date("20260704") is not None
