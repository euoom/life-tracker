from fastapi import FastAPI, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel
from typing import Optional, Any
from datetime import datetime
from pathlib import Path

app = FastAPI(
    title="Life Tracker Context Hub",
    description="Life tracker event receiver and policy engine prototype",
    version="0.1.0"
)

class NetworkEvent(BaseModel):
    event: Optional[str] = "unknown"
    ssid: Optional[str] = None
    device: Optional[str] = "iPhone"
    abc: Optional[str] = None  # 테스트용 필드 수용
    extra: Optional[Any] = None

@app.get("/")
def read_root():
    return {
        "service": "custom-youtube-gateway",
        "message": "hello from custom-youtube gateway",
        "timestamp": datetime.now().isoformat()
    }

@app.get("/rootCA.pem", include_in_schema=False)
def download_root_ca():
    return FileResponse(Path(__file__).parent / "certs" / "rootCA.pem", media_type="application/x-pem-file")

@app.get("/rootCA.cer", include_in_schema=False)
def download_root_ca_for_ios():
    return FileResponse(Path(__file__).parent / "certs" / "rootCA.cer", media_type="application/pkix-cert")

@app.post("/api/tracker/network")
async def receive_network_event(event: NetworkEvent, request: Request):
    client_ip = request.client.host if request.client else "unknown"
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    # 요청 수신 Echo 로그 출력
    print(f"[{now_str}] [Network Event Received] Client: {client_ip} | Event: {event.event} | SSID: {event.ssid} | Device: {event.device}")
    
    # 프로토타입 Echo 응답
    return {
        "status": "ok",
        "message": "Network event received (Echo Prototype)",
        "received_at": now_str,
        "client_ip": client_ip,
        "echo": event.model_dump()
    }

@app.get("/api/tracker/status")
def get_status():
    # 현재 상태 조회 프로토타입 스텁
    return {
        "is_home": True,
        "focus_mode": True,
        "active_tasks_count": 1,
        "message": "This is a prototype status endpoint."
    }
