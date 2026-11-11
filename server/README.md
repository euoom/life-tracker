# Ingestion server

A separate first implementation; legacy root `main.py` and `dns_server.py` are
preserved. Run from this folder. Default project port: **18765**.

```sh
cp .env.example .env
# Fill LIFE_TRACKER_TOKEN with at least 24 random characters; do not reuse a password.
uv sync
uv run --env-file .env uvicorn life_tracker.app:app --host 127.0.0.1 --port 18765
```

The local health endpoint is `http://localhost:18765/health`, Swagger documentation
is `/docs`. For an iPhone, bind to a reachable private interface and use its LAN
or WireGuard address, not localhost. The WSL/Windows route, firewall and VPN
activation are installation tasks; they are not modified by this repository.

A missing/short token prevents startup. Every data endpoint uses
`Authorization: Bearer YOUR_TOKEN`. `/health` returns no personal data and is
public. Use TLS or a trusted private network; do not expose HTTP/token traffic to
the public internet. Production transport configuration is not included.

Runtime data defaults to `~/.local/share/life-tracker`, outside both repositories:
`tracker.sqlite3` and `audio/UUID.m4a`. No retention sweep or delete endpoint is
implemented. Originals remain until explicitly removed or a later policy is set.
This database stores ingestion state; event/daily Markdown remains the final
knowledge-base record once that integration is implemented.

## API

- `POST /api/v1/events`: JSON with `event_id` (UUID), `device_id`, `kind`
  (`message`, `location`, `network`, `recording`, `call`), timezone-aware
  `recorded_at`, and `payload`. Event ID plus identical content is idempotent;
  conflicting reuse returns 409.
- `PUT /api/v1/audio/UUID`: raw M4A bytes, `Content-Type: audio/mp4`,
  `X-Device-ID`, `X-Recorded-At` (ISO 8601 with timezone), `X-Content-SHA256`.
  Default maximum is 128 MiB. The server streams to a temporary file, validates
  the SHA256 and persists receipt metadata. Existing IDs cannot be overwritten
  with different bytes or metadata. Payload MIME is checked, codec validity is
  not decoded/verified in this slice.
- `GET /api/v1/status`: counts, total audio bytes and analysis state.
- `GET /api/v1/events?limit=100`: most recently received events (maximum 500).
- `GET /api/v1/audio?limit=100`: recent audio metadata (maximum 500).

Example event (test data, not actual correspondence):

```json
{
  "event_id": "ac924820-f8d0-41dc-883f-83d4ca11ab15",
  "device_id": "iphone-test",
  "kind": "message",
  "recorded_at": "2026-11-11T12:00:00+09:00",
  "payload": {"text": "내일 방문 예정입니다", "sender": "test"}
}
```

## Verification

```sh
uv run pytest -q
```

Tests use temporary storage and no real phone contents. Gemini transcription,
YouTube browser operation, historical backup import, agent execution and
knowledge-base writing are not implemented. This server never starts automatic
analysis or edits private events/daily files from uploaded data.
