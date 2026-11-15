from urllib import response

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app, raise_server_exceptions=False)

def test_root():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["status"] == "running"


def test_health():
    response = client.get("/health")
    assert response.status_code == 500
    assert response.json() == {"detail": "intentional rollback test"}

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
