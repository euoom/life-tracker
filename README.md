# Life Tracker (Context Hub Prototype)

단축어 및 외부 네트워크 이벤트를 수신하여 에코(Echo)로 응답하는 초경량 프로토타입 서버입니다.

## 실행 방법

```bash
cd repository/life-tracker
uv run uvicorn main:app --host 0.0.0.0 --port 24700 --reload
# 또는 python -m uvicorn main:app --host 0.0.0.0 --port 24700 --reload
```

## 주요 엔드포인트

- `GET /` : 서버 헬스체크
- `POST /api/tracker/network` : 네트워크 이벤트 수신 및 Echo 반환
  - Payload 예시:
    ```json
    {
      "event": "home_wifi_connected",
      "ssid": "MyHome_5G",
      "device": "iPhone"
    }
    ```
- `GET /api/tracker/status` : 현재 상태 조회 스텁

## 앱·서버 수집 시제품

현재 개발은 `ios/`와 `server/`에서 진행합니다. 위의 루트 Echo 서버는
기존 실험으로 보존합니다. 새 수집 서버 포트는 **18765**입니다.

- [서버 실행·API·테스트](server/README.md)
- [아이폰 빌드·설치·단축어·실기기 시험](ios/README.md)
- [수동 구조 지도](docs/architecture.md)

아이폰 소스는 GitHub Actions의 Xcode 빌드를 통과했으며 실기기에서는 아직 검증하지 않았습니다. API 통합 테스트와
아이폰 컴파일·설치 검증은 별도입니다. 실제 기록 수집은 설치와 설정 후에만
시작하며 PC 원본은 자동 삭제하지 않습니다.
