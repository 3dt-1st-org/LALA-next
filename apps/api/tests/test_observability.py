from __future__ import annotations

import logging


def test_request_duration_header_is_returned(client):
    response = client.get("/healthz")

    assert response.status_code == 200
    assert response.headers["X-Request-ID"]
    assert float(response.headers["X-Request-Duration-Ms"]) >= 0


def test_request_logging_omits_auth_headers_and_query_string(client, auth_headers, caplog):
    caplog.set_level(logging.INFO, logger="lala_next.api")

    response = client.get(
        "/api/v1/places?token=should-not-be-logged",
        headers={
            **auth_headers,
            "Authorization": "Bearer should-not-be-logged",
            "X-Request-ID": "request-log-test",
        },
    )

    assert response.status_code == 200
    records = [
        record
        for record in caplog.records
        if record.name == "lala_next.api" and record.getMessage().startswith("request_completed")
    ]
    assert records
    record = records[-1]
    assert record.request_id == "request-log-test"
    assert record.method == "GET"
    assert record.path == "/api/v1/places"
    assert record.status_code == 200
    assert record.duration_ms >= 0
    rendered = " ".join(record.getMessage() for record in records)
    assert "request_id=request-log-test" in rendered
    assert "method=GET" in rendered
    assert "path=/api/v1/places" in rendered
    assert "status_code=200" in rendered
    assert "should-not-be-logged" not in rendered
