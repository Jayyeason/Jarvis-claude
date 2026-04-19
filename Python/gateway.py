import sys
import os
import json
from pathlib import Path
from typing import Optional
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

sys.path.insert(0, os.path.dirname(__file__))

from providers.provider_factory import create_provider
from providers.provider_configs import PROVIDER_CONFIGS
from agent.jarvis_agent import JarvisAgent


# ── Config persistence ────────────────────────────────────────────────────────

CONFIG_PATH = Path.home() / ".jarvis" / "api_config.json"


def load_config() -> dict:
    if CONFIG_PATH.exists():
        try:
            return json.loads(CONFIG_PATH.read_text())
        except Exception:
            return {}
    return {}


def save_config(data: dict):
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(data, indent=2, ensure_ascii=False))


# ── Pydantic models ───────────────────────────────────────────────────────────

class ChatRequest(BaseModel):
    message: str = ""
    image: Optional[str] = None
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

    # Auto-restore last active provider from disk
    cfg = load_config()
    pid = cfg.get("active_provider_id")
    mid = cfg.get("active_model_id")
    if pid and mid:
        pcfg = cfg.get("providers", {}).get(pid, {})
        try:
            provider = create_provider(pid, {
                "api_key":        pcfg.get("api_key", ""),
                "model":          mid,
                "base_url":       pcfg.get("base_url"),
                "aws_access_key": pcfg.get("aws_access_key"),
                "aws_secret_key": pcfg.get("aws_secret_key"),
                "region":         pcfg.get("region"),
            })
            app.state.active_provider    = provider
            app.state.active_provider_id = pid
            app.state.active_model_id    = mid
            print(f"[Gateway] Restored provider: {pid}/{mid}")
        except Exception as e:
            print(f"[Gateway] Could not restore provider: {e}")

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


@app.get("/config")
async def get_config():
    """Return current config (no API keys exposed)."""
    cfg = load_config()
    providers_display = {}
    for pid, pcfg in cfg.get("providers", {}).items():
        providers_display[pid] = {
            "model_id":   pcfg.get("model_id"),
            "base_url":   pcfg.get("base_url"),
            "configured": pcfg.get("configured", False),
        }
    return {
        "active_provider_id": cfg.get("active_provider_id"),
        "active_model_id":    cfg.get("active_model_id"),
        "providers":          providers_display,
    }


@app.post("/settings")
async def update_settings(req: SettingsRequest):
    """Save provider config to disk and activate it."""
    try:
        provider_cfg = {
            "api_key":        req.api_key,
            "model":          req.model_id,
            "base_url":       req.base_url,
            "aws_access_key": req.aws_access_key,
            "aws_secret_key": req.aws_secret_key,
            "region":         req.region,
        }
        provider = create_provider(req.provider_id, provider_cfg)

        app.state.active_provider    = provider
        app.state.active_provider_id = req.provider_id
        app.state.active_model_id    = req.model_id

        # Persist to disk
        cfg = load_config()
        cfg["active_provider_id"] = req.provider_id
        cfg["active_model_id"]    = req.model_id
        providers = cfg.get("providers", {})
        providers[req.provider_id] = {
            "api_key":        req.api_key,
            "model_id":       req.model_id,
            "base_url":       req.base_url,
            "aws_access_key": req.aws_access_key,
            "aws_secret_key": req.aws_secret_key,
            "region":         req.region,
            "configured":     True,
        }
        cfg["providers"] = providers
        save_config(cfg)

        return {"status": "ok", "provider": req.provider_id, "model": req.model_id}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.post("/verify")
async def verify_provider(req: VerifyRequest):
    """Verify API key without saving to disk."""
    try:
        config = {
            "api_key":        req.api_key,
            "model":          req.model_id or _default_model(req.provider_id),
            "base_url":       req.base_url,
            "aws_access_key": req.aws_access_key,
            "aws_secret_key": req.aws_secret_key,
            "region":         req.region,
        }
        provider = create_provider(provider_id=req.provider_id, config=config)
        models = await provider.verify()
        return {"status": "ok", "models": models}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest):
    if app.state.active_provider is None:
        return ChatResponse(reply="请先配置云端 API", error="no_provider")
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


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8765, log_level="warning")
