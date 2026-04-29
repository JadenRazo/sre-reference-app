import json
import logging

import pytest

import main


@pytest.fixture
def client():
    main.app.config["TESTING"] = True
    with main.app.test_client() as c:
        yield c


def test_health_returns_200(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json["status"] == "ok"
    assert response.json["app"] == main.APP_NAME


def test_health_unaffected_by_error_rate(client, monkeypatch):
    monkeypatch.setattr(main, "ERROR_RATE", 1.0)
    response = client.get("/health")
    assert response.status_code == 200


def test_root_succeeds_when_error_rate_zero(client, monkeypatch):
    monkeypatch.setattr(main, "ERROR_RATE", 0.0)
    response = client.get("/")
    assert response.status_code == 200
    assert response.json["hello"] == "world"


def test_root_fails_when_error_rate_one(client, monkeypatch):
    monkeypatch.setattr(main, "ERROR_RATE", 1.0)
    response = client.get("/")
    assert response.status_code == 500
    assert response.json["error"] == "intermittent"


def test_request_id_is_propagated_from_header(client):
    response = client.get("/health", headers={"X-Request-ID": "test-12345"})
    assert response.headers["X-Request-ID"] == "test-12345"


def test_request_id_is_generated_when_header_absent(client):
    response = client.get("/health")
    rid = response.headers["X-Request-ID"]
    assert len(rid) == 36 and rid.count("-") == 4


def test_request_log_is_valid_json_with_required_fields(client, caplog):
    with caplog.at_level(logging.INFO, logger=main.APP_NAME):
        client.get("/health", headers={"X-Request-ID": "trace-abc"})

    request_records = [r for r in caplog.records if r.getMessage() == "request"]
    assert len(request_records) == 1

    payload = json.loads(main.JsonFormatter().format(request_records[0]))
    for field in ("request_id", "method", "path", "status", "duration_ms"):
        assert field in payload
    assert payload["request_id"] == "trace-abc"
    assert payload["status"] == 200
    assert payload["path"] == "/health"
