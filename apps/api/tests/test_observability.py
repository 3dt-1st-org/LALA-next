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


def test_metrics_endpoint_is_public_and_omits_query_and_auth_values(client, auth_headers):
    marker = "should-not-be-exported"
    response = client.get(
        f"/api/v1/places?token={marker}",
        headers={
            **auth_headers,
            "Authorization": f"Bearer {marker}",
            "X-Request-ID": "metrics-test",
        },
    )
    assert response.status_code == 200

    metrics = client.get(f"/metrics?token={marker}")

    assert metrics.status_code == 200
    assert metrics.headers["content-type"].startswith("text/plain")
    body = metrics.text
    assert "lala_next_process_uptime_seconds" in body
    assert "lala_next_http_requests_total" in body
    assert 'method="GET",path="/api/v1/places",status_code="200",status_class="2xx"' in body
    assert 'path="/metrics"' not in body
    assert marker not in body
    assert "Authorization" not in body
    assert "X-API-Key" not in body

    second_metrics = client.get("/metrics")
    assert 'path="/metrics"' not in second_metrics.text


def test_metrics_records_status_classes_for_errors(client, api_key):
    response = client.get("/api/v1/places", headers={"X-API-Key": "wrong"})
    assert response.status_code == 401

    metrics = client.get("/metrics")

    assert (
        'method="GET",path="/api/v1/places",status_code="401",status_class="4xx"'
        in metrics.text
    )


def test_unmatched_paths_are_collapsed_in_logs_and_metrics(client, caplog):
    caplog.set_level(logging.INFO, logger="lala_next.api")

    response = client.get("/missing/should-not-be-path-label?token=should-not-be-exported")
    assert response.status_code == 404

    metrics = client.get("/metrics")
    assert 'path="__unmatched__",status_code="404",status_class="4xx"' in metrics.text
    assert "should-not-be-path-label" not in metrics.text
    assert "should-not-be-exported" not in metrics.text

    rendered = " ".join(
        record.getMessage()
        for record in caplog.records
        if record.name == "lala_next.api" and record.getMessage().startswith("request_completed")
    )
    assert "path=__unmatched__" in rendered
    assert "should-not-be-path-label" not in rendered
    assert "should-not-be-exported" not in rendered
