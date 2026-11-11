from contextlib import asynccontextmanager, contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import secrets
import sqlite3
import tempfile
from typing import Annotated, Literal
from uuid import UUID

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import AwareDatetime, BaseModel, Field, model_validator


class Event(BaseModel):
    event_id: UUID
    device_id: str = Field(min_length=1, max_length=128)
    kind: Literal["message", "location", "network", "recording", "call"]
    recorded_at: AwareDatetime
    payload: dict

    @model_validator(mode="after")
    def validate_payload(self):
        if len(json.dumps(self.payload).encode()) > 65536:
            raise ValueError("Event payload must fit in 64 KiB")
        if self.kind == "location":
            latitude = self.payload.get("latitude")
            longitude = self.payload.get("longitude")
            if not isinstance(latitude, (float, int)) or not -90 <= latitude <= 90:
                raise ValueError("Invalid latitude")
            if not isinstance(longitude, (float, int)) or not -180 <= longitude <= 180:
                raise ValueError("Invalid longitude")
        if self.kind == "message" and not isinstance(self.payload.get("text"), str):
            raise ValueError("Message requires text")
        return self


def create_app(data_dir: Path | None = None, token: str | None = None, max_audio_bytes: int | None = None):
    secret = token if token is not None else os.environ.get("LIFE_TRACKER_TOKEN", "")
    root = data_dir or Path(os.environ.get("LIFE_TRACKER_DATA_DIR", "~/.local/share/life-tracker")).expanduser()
    maximum = max_audio_bytes or int(os.environ.get("LIFE_TRACKER_MAX_AUDIO_BYTES", "134217728"))

    @contextmanager
    def connect():
        connection = sqlite3.connect(root / "tracker.sqlite3", timeout=30)
        connection.row_factory = sqlite3.Row
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    @asynccontextmanager
    async def lifespan(app):
        if len(secret) < 24:
            raise RuntimeError("Set LIFE_TRACKER_TOKEN to a random secret of at least 24 characters")
        root.mkdir(parents=True, exist_ok=True, mode=0o700)
        (root / "audio").mkdir(exist_ok=True, mode=0o700)
        with connect() as connection:
            connection.executescript("""
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS events (
                    event_id TEXT PRIMARY KEY, device_id TEXT NOT NULL,
                    kind TEXT NOT NULL, recorded_at TEXT NOT NULL,
                    payload TEXT NOT NULL, fingerprint TEXT NOT NULL,
                    received_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS audio (
                    recording_id TEXT PRIMARY KEY, device_id TEXT NOT NULL,
                    recorded_at TEXT NOT NULL, sha256 TEXT NOT NULL,
                    size_bytes INTEGER NOT NULL, path TEXT NOT NULL,
                    received_at TEXT NOT NULL
                );
            """)
        yield

    app = FastAPI(title="Life Tracker", version="0.1.0", lifespan=lifespan)
    bearer = HTTPBearer(auto_error=False)

    def authorize(credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)]):
        if credentials is None or not secrets.compare_digest(credentials.credentials, secret):
            raise HTTPException(401, "Invalid bearer token", headers={"WWW-Authenticate": "Bearer"})

    @app.get("/health")
    def health():
        return {"service": "life-tracker", "status": "ok"}

    @app.post("/api/v1/events", dependencies=[Depends(authorize)])
    def receive_event(event: Event):
        body = event.model_dump(mode="json")
        canonical = json.dumps(body, sort_keys=True, separators=(",", ":"))
        fingerprint = hashlib.sha256(canonical.encode()).hexdigest()
        with connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            existing = connection.execute("SELECT fingerprint FROM events WHERE event_id=?", (str(event.event_id),)).fetchone()
            if existing:
                if existing["fingerprint"] != fingerprint:
                    raise HTTPException(409, "Event ID already has different content")
                return {"event_id": str(event.event_id), "stored": True, "duplicate": True}
            connection.execute("INSERT INTO events VALUES (?, ?, ?, ?, ?, ?, ?)", (
                str(event.event_id), event.device_id, event.kind, event.recorded_at.isoformat(),
                json.dumps(event.payload, ensure_ascii=False), fingerprint, datetime.now(timezone.utc).isoformat(),
            ))
        return {"event_id": str(event.event_id), "stored": True, "duplicate": False}

    @app.put("/api/v1/audio/{recording_id}", dependencies=[Depends(authorize)])
    async def receive_audio(
        recording_id: UUID, request: Request,
        x_device_id: Annotated[str, Header(min_length=1, max_length=128)],
        x_recorded_at: Annotated[AwareDatetime, Header()],
        x_content_sha256: Annotated[str, Header(pattern=r"^[a-f0-9]{64}$")],
    ):
        if request.headers.get("content-type", "").split(";")[0] != "audio/mp4":
            raise HTTPException(415, "Expected audio/mp4 (AAC in M4A)")
        temporary = None
        try:
            size = 0
            digest = hashlib.sha256()
            with tempfile.NamedTemporaryFile(dir=root / "audio", prefix=".upload-", delete=False) as stream:
                temporary = Path(stream.name)
                async for chunk in request.stream():
                    size += len(chunk)
                    if size > maximum:
                        raise HTTPException(413, "Audio exceeds configured limit")
                    digest.update(chunk)
                    stream.write(chunk)
                stream.flush()
                os.fsync(stream.fileno())
            if not size:
                raise HTTPException(400, "Empty recording")
            checksum = digest.hexdigest()
            if checksum != x_content_sha256:
                raise HTTPException(422, "Audio checksum mismatch")
            destination = root / "audio" / f"{recording_id}.m4a"
            with connect() as connection:
                connection.execute("BEGIN IMMEDIATE")
                existing = connection.execute("SELECT * FROM audio WHERE recording_id=?", (str(recording_id),)).fetchone()
                if existing:
                    if (existing["sha256"], existing["device_id"], existing["recorded_at"]) != (checksum, x_device_id, x_recorded_at.isoformat()):
                        raise HTTPException(409, "Recording ID already has different content or metadata")
                    return {"recording_id": str(recording_id), "stored": True, "duplicate": True, "sha256": checksum}
                os.replace(temporary, destination)
                connection.execute("INSERT INTO audio VALUES (?, ?, ?, ?, ?, ?, ?)", (
                    str(recording_id), x_device_id, x_recorded_at.isoformat(), checksum,
                    size, str(destination), datetime.now(timezone.utc).isoformat(),
                ))
            return {"recording_id": str(recording_id), "stored": True, "duplicate": False, "sha256": checksum}
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)

    @app.get("/api/v1/status", dependencies=[Depends(authorize)])
    def status():
        with connect() as connection:
            events = connection.execute("SELECT kind, COUNT(*) AS count FROM events GROUP BY kind").fetchall()
            audio = connection.execute("SELECT COUNT(*) AS count, COALESCE(SUM(size_bytes), 0) AS bytes FROM audio").fetchone()
        return {"events": {row["kind"]: row["count"] for row in events}, "audio": dict(audio), "automatic_analysis": False}

    @app.get("/api/v1/events", dependencies=[Depends(authorize)])
    def events(limit: Annotated[int, Query(ge=1, le=500)] = 100):
        with connect() as connection:
            rows = connection.execute("SELECT event_id, device_id, kind, recorded_at, payload, received_at FROM events ORDER BY received_at DESC LIMIT ?", (limit,)).fetchall()
        return [{**dict(row), "payload": json.loads(row["payload"])} for row in rows]

    @app.get("/api/v1/audio", dependencies=[Depends(authorize)])
    def recordings(limit: Annotated[int, Query(ge=1, le=500)] = 100):
        with connect() as connection:
            rows = connection.execute("SELECT recording_id, device_id, recorded_at, sha256, size_bytes, received_at FROM audio ORDER BY received_at DESC LIMIT ?", (limit,)).fetchall()
        return [dict(row) for row in rows]

    return app


app = create_app()
