from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from database import engine, Base
from routers import auth, payments, sync, vaults, tx
from typing import List

# Create DB tables
Base.metadata.create_all(bind=engine)

app = FastAPI(title="SuiFlow API", description="Offline-first Programmable Payments MVP on Sui")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/api/auth", tags=["auth"])
app.include_router(payments.router, prefix="/api/payments", tags=["payments"])
app.include_router(sync.router, prefix="/api/sync", tags=["sync"])
app.include_router(vaults.router, prefix="/api/vaults", tags=["vaults"])
app.include_router(tx.router, prefix="/api/tx", tags=["tx"])

@app.get("/")
def read_root():
    return {"message": "Welcome to SuiFlow API"}

# Simple WebSocket connection manager for real-time status updates
class ConnectionManager:
    def __init__(self):
        self.active_connections: dict[str, WebSocket] = {}

    async def connect(self, websocket: WebSocket, phone_number: str):
        await websocket.accept()
        self.active_connections[phone_number] = websocket

    def disconnect(self, phone_number: str):
        if phone_number in self.active_connections:
            del self.active_connections[phone_number]

    async def send_personal_message(self, message: str, phone_number: str):
        if phone_number in self.active_connections:
            await self.active_connections[phone_number].send_text(message)

manager = ConnectionManager()

@app.websocket("/ws/{phone_number}")
async def websocket_endpoint(websocket: WebSocket, phone_number: str):
    await manager.connect(websocket, phone_number)
    try:
        while True:
            data = await websocket.receive_text()
            # Echo or handle incoming ws data
            await manager.send_personal_message(f"Echo: {data}", phone_number)
    except WebSocketDisconnect:
        manager.disconnect(phone_number)
