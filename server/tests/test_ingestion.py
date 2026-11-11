import hashlib
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from life_tracker.app import create_app

TOKEN = "test-only-secret-at-least-24-characters"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


@pytest.fixture
def client(tmp_path):
    with TestClient(create_app(tmp_path, TOKEN, max_audio_bytes=100)) as connection:
        yield connection, tmp_path


def event(kind="message", payload=None):
    return {"event_id": str(uuid4()), "device_id": "iphone-test", "kind": kind,
            "recorded_at": "2026-11-11T03:00:00Z", "payload": payload or {"text": "내일 점검 예정", "sender": "기관"}}


def audio_headers(content=b"test recording"):
    return {**AUTH, "Content-Type": "audio/mp4", "X-Device-ID": "iphone-test",
            "X-Recorded-At": "2026-11-11T03:00:00Z", "X-Content-SHA256": hashlib.sha256(content).hexdigest()}


def test_authentication(client):
    connection, _ = client
    assert connection.get("/health").status_code == 200
    for headers in ({}, {"Authorization": "Bearer wrong"}):
        assert connection.get("/api/v1/events", headers=headers).status_code == 401
        assert connection.post("/api/v1/events", json=event(), headers=headers).status_code == 401


def test_event_retry_conflict_and_readback(client):
    connection, _ = client
    body = event()
    assert connection.post("/api/v1/events", json=body, headers=AUTH).json()["duplicate"] is False
    assert connection.post("/api/v1/events", json=body, headers=AUTH).json()["duplicate"] is True
    body["payload"]["text"] = "changed"
    assert connection.post("/api/v1/events", json=body, headers=AUTH).status_code == 409
    rows = connection.get("/api/v1/events", headers=AUTH).json()
    assert len(rows) == 1
    assert rows[0]["payload"]["text"] == "내일 점검 예정"


def test_location_and_timestamp_validation(client):
    connection, _ = client
    for payload in ({"latitude": 91, "longitude": 0}, {"latitude": 1, "longitude": "invalid"}):
        assert connection.post("/api/v1/events", json=event("location", payload), headers=AUTH).status_code == 422
    body = event("location", {"latitude": 37.5, "longitude": 127.0})
    assert connection.post("/api/v1/events", json=body, headers=AUTH).status_code == 200
    body["event_id"] = str(uuid4())
    body["recorded_at"] = "2026-11-11T03:00:00"
    assert connection.post("/api/v1/events", json=body, headers=AUTH).status_code == 422


def test_audio_integrity_idempotency_retention(client):
    connection, root = client
    recording_id = str(uuid4())
    url = f"/api/v1/audio/{recording_id}"
    content = b"test recording"
    first = connection.put(url, content=content, headers=audio_headers(content))
    assert first.status_code == 200
    assert first.json()["sha256"] == hashlib.sha256(content).hexdigest()
    assert connection.put(url, content=content, headers=audio_headers(content)).json()["duplicate"] is True
    assert connection.put(url, content=b"different", headers=audio_headers(b"different")).status_code == 409
    assert (root / "audio" / f"{recording_id}.m4a").read_bytes() == content
    assert len(connection.get("/api/v1/audio", headers=AUTH).json()) == 1
    assert connection.get("/api/v1/status", headers=AUTH).json()["audio"]["count"] == 1


def test_audio_failures_leave_no_receipt_or_temporary_file(client):
    connection, root = client
    url = f"/api/v1/audio/{uuid4()}"
    for content, headers, expected in (
        (b"", audio_headers(b""), 400),
        (b"x" * 101, audio_headers(b"x" * 101), 413),
        (b"wrong", audio_headers(), 422),
        (b"data", {**audio_headers(b"data"), "Content-Type": "text/plain"}, 415),
    ):
        assert connection.put(url, content=content, headers=headers).status_code == expected
    assert list((root / "audio").iterdir()) == []
    assert connection.get("/api/v1/audio", headers=AUTH).json() == []


def test_storage_survives_restart(tmp_path):
    body = event()
    with TestClient(create_app(tmp_path, TOKEN)) as connection:
        connection.post("/api/v1/events", json=body, headers=AUTH).raise_for_status()
    with TestClient(create_app(tmp_path, TOKEN)) as connection:
        assert connection.get("/api/v1/events", headers=AUTH).json()[0]["event_id"] == body["event_id"]


def test_missing_token_fails_closed(tmp_path):
    with pytest.raises(RuntimeError, match="LIFE_TRACKER_TOKEN"):
        with TestClient(create_app(tmp_path, "")):
            pass
