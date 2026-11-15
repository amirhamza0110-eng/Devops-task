from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app, raise_server_exceptions=False)


def test_root():
    r = client.get("/")
    assert r.status_code == 200
    body = r.json()
    assert body["message"] == "Hello from DevOps Task!"
    assert body["status"] == "running"
    assert "version" in body


def test_health():
    assert client.get("/health").json() == {"status": "ok"}


def test_metrics_exposes_required_series():
    client.get("/")
    client.get("/boom")
    text = client.get("/metrics").text
    assert "http_requests_total" in text
    assert "http_errors_total" in text
    assert "http_request_duration_seconds_bucket" in text


def test_unknown_path_is_404_and_low_cardinality():
    assert client.get("/nope-123").status_code == 404
    assert 'path="unmatched"' in client.get("/metrics").text
