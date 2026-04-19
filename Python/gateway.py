import sys
import os
import asyncio
from typing import Optional
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# Add project root to path so sub-modules can import each other
sys.path.insert(0, os.path.dirname(__file__))

from providers.provider_factory import create_provider
from providers.provider_configs import PROVIDER_CONFIGS
from agent.jarvis_agent import JarvisAgent


# ── Pydantic models ──────────────────────────────────────────────────────────

class ChatRequest(BaseModel):
    message: str = ""
    image: Optional[str] = None  # base64 JPEG
    session_id: Optional[str] = None


class ChatResponse(BaseModel):
    event_type: Optional[str] = None
    title: Optional[str] = None
    start_time: Optional[str] = None
    end_time: Optional[str] = None
    needs_duration: bool = False
    location: Optional[str] = None
    notes: Optional[str] = None
    due_date: Optional[str] = None
    due_time: Optional[str] = None
    priority: Optional[str] = None
    reply: Optional[str] = None
    error: Optional[str] = None


class SettingsRequest(BaseModel):
    provider_id: str
    model_id: str
    api_key: str = ""
    base_url: Optional[str] = None
    aws_access_key: Optional[str] = None
    aws_secret_key: Optional[str] = None
    region: Optional[str] = None


class VerifyRequest(BaseModel):
    provider_id: str
    api_key: str = ""
    base_url: Optional[str] = None
    model_id: str = ""
    aws_access_key: Optional[str] = None
    aws_secret_key: Optional[str] = None
    region: Optional[str] = None


# ── App ───────────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.active_provider = None
    app.state.active_provider_id = None
    app.state.active_model_id = None
    app.state.agent = JarvisAgent()
    yield


app = FastAPI(title="Jarvis Gateway", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Endpoints ─────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {
        "status": "ok",
        "provider": app.state.active_provider_id,
        "model": app.state.active_model_id,
    }


@app.post("/settings")
async def update_settings(req: SettingsRequest):
    try:
        config = {
            "api_key": req.api_key,
            "model": req.model_id,
            "base_url": req.base_url,
        }
        if req.aws_access_key:
            config["aws_access_key"] = req.aws_access_key
            config["aws_secret_key"] = req.aws_secret_key
            config["region"] = req.region or "us-east-1"

        provider = create_provider(
            provider_id=req.provider_id,
            config=config,
        )
        app.state.active_provider = provider
        app.state.active_provider_id = req.provider_id
        app.state.active_model_id = req.model_id

        return {"status": "ok", "provider": req.provider_id, "model": req.model_id}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.post("/verify")
async def verify_provider(req: VerifyRequest):
    try:
        config = {
            "api_key": req.api_key,
            "model": req.model_id or _default_model(req.provider_id),
            "base_url": req.base_url,
        }
        if req.aws_access_key:
            config["aws_access_key"] = req.aws_access_key
            config["aws_secret_key"] = req.aws_secret_key
            config["region"] = req.region or "us-east-1"

        provider = create_provider(provider_id=req.provider_id, config=config)
        models = await provider.verify()
        return {"status": "ok", "models": models}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest):
    if app.state.active_provider is None:
        return ChatResponse(
            reply="请先配置云端 API",
            error="no_provider",
        )
    try:
        result = await app.state.agent.run(
            message=req.message,
            image_base64=req.image,
            session_id=req.session_id,
            provider=app.state.active_provider,
        )
        return ChatResponse(**{k: v for k, v in result.items() if k in ChatResponse.model_fields})
    except Exception as e:
        return ChatResponse(reply="识别失败，请重试", error=str(e))


def _default_model(provider_id: str) -> str:
    cfg = PROVIDER_CONFIGS.get(provider_id, {})
    models = cfg.get("preset_models", [])
    return models[0] if models else ""


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8765, log_level="warning")
