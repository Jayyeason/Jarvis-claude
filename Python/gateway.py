import sys
import os
import asyncio
import hashlib
import importlib.util
import json
import logging
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional
from contextlib import asynccontextmanager
from uuid import uuid4

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

sys.path.insert(0, os.path.dirname(__file__))

from providers.provider_factory import create_provider
from providers.provider_configs import PROVIDER_CONFIGS
from providers.local_model_registry import (
    LocalModelRegistry,
    MODELS_DIR,
    RECOMMENDED_MLX_MODELS,
    safe_model_id,
)
from agent import JarvisAgent
from agent.assistant_chat import (
    assistant_system_prompt,
    contextual_schedule_creation_text,
    cron_command_payload,
    cron_delete_id,
    heuristic_action_plan,
    is_cron_create_request,
    is_cron_delete_request,
    is_cron_help_request,
    is_cron_list_request,
    is_contextual_local_operation_request,
    is_memory_update_request,
    is_schedule_creation_request,
    is_local_operation_request,
    is_slash_list_request,
    plan_assistant_action,
    plan_cron_task,
    parse_preference_update,
    preference_reply,
)
from agent.cron_memory import append_cron_task, cron_help_text, delete_cron_task, describe_cron_expr, read_cron_tasks
from agent.heartbeat import HeartbeatEngine
from contracts import (
    ActivateModelRequest,
    AgentResponse,
    AssistantChatRequest,
    AssistantChatResponse,
    AvailableModelsResponse,
    CalendarEventSnapshot,
    ChatRequest,
    GatewayConfig,
    GatewayDetailResponse,
    HeartbeatTickRequest,
    HeartbeatTickResponse,
    LocalModelsResponse,
    MemoryFileUpdateRequest,
    MemoryFileUpdateResponse,
    MemoryFilesResponse,
    MemoryStatus,
    MemoryFeedbackRequest,
    MemoryFeedbackResponse,
    MemoryPreferencesPatch,
    MemoryPreferencesResponse,
    ModelActionRequest,
    ModelDownloadRequest,
    ModelDownloadStatus,
    ModelDownloadStatusResponse,
    ProactiveEvent,
    ReminderSnapshot,
    SettingsRequest,
    VerifyRequest,
    VerifyResponse,
)
from logger import LOG_PATH, configure_logging


configure_logging()
logger = logging.getLogger("gateway")


# ── Config persistence ────────────────────────────────────────────────────────

CONFIG_PATH = Path.home() / ".jarvis" / "api_config.json"


def _migrate_config(data: dict) -> tuple[dict, bool]:
    changed = False
    providers = data.get("providers", {})
    deepseek_cfg = providers.get("deepseek")
    deepseek_models = PROVIDER_CONFIGS.get("deepseek", {}).get("preset_models", [])
    if isinstance(deepseek_cfg, dict) and deepseek_models:
        model_id = deepseek_cfg.get("model_id")
        if model_id and model_id not in deepseek_models:
            deepseek_cfg["model_id"] = deepseek_models[0]
            if data.get("active_provider_id") == "deepseek":
                data["active_model_id"] = deepseek_models[0]
            changed = True
    return data, changed


def load_config() -> dict:
    if CONFIG_PATH.exists():
        try:
            data = json.loads(CONFIG_PATH.read_text())
            data, changed = _migrate_config(data)
            if changed:
                save_config(data)
            return data
        except Exception:
            logger.exception("Could not load config from %s", CONFIG_PATH)
            return {}
    return {}


def save_config(data: dict):
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(data, indent=2, ensure_ascii=False))


def _secret_key_id(secret: str) -> str:
    return "key_" + hashlib.sha256(secret.encode("utf-8")).hexdigest()[:16]


def _mask_secret(secret: str) -> str:
    value = secret.strip()
    if not value:
        return ""
    if len(value) <= 8:
        return f"{value[:2]}**{value[-2:]}"
    return f"{value[:6]}**{value[-4:]}"


def _api_key_entry(secret: str, created_at: Optional[str] = None, key_id: Optional[str] = None) -> dict:
    value = secret.strip()
    return {
        "id": key_id or _secret_key_id(value),
        "api_key": value,
        "created_at": created_at or datetime.now(timezone.utc).isoformat(),
    }


def _normalize_api_keys(provider_cfg: dict) -> tuple[list[dict], Optional[str]]:
    raw_entries = provider_cfg.get("api_keys") or []
    entries: list[dict] = []
    seen_secret_ids: set[str] = set()
    seen_ids: set[str] = set()

    if isinstance(raw_entries, list):
        for item in raw_entries:
            if not isinstance(item, dict):
                continue
            secret = str(item.get("api_key") or "").strip()
            if not secret:
                continue
            secret_id = _secret_key_id(secret)
            key_id = str(item.get("id") or secret_id)
            if key_id in seen_ids or secret_id in seen_secret_ids:
                continue
            entries.append(_api_key_entry(secret, item.get("created_at"), key_id))
            seen_ids.add(key_id)
            seen_secret_ids.add(secret_id)

    legacy_secret = str(provider_cfg.get("api_key") or "").strip()
    legacy_id = _secret_key_id(legacy_secret) if legacy_secret else None
    if legacy_secret and legacy_id not in seen_secret_ids:
        entries.append(_api_key_entry(legacy_secret, provider_cfg.get("created_at"), legacy_id))
        seen_ids.add(legacy_id)
        seen_secret_ids.add(legacy_id)

    active_id = provider_cfg.get("active_api_key_id")
    ids = {item["id"] for item in entries}
    if active_id not in ids:
        if legacy_id in ids:
            active_id = legacy_id
        elif entries:
            active_id = entries[0]["id"]
        else:
            active_id = None

    if entries:
        provider_cfg["api_keys"] = entries
        provider_cfg["active_api_key_id"] = active_id
        provider_cfg["api_key"] = next((item["api_key"] for item in entries if item["id"] == active_id), entries[0]["api_key"])
    else:
        provider_cfg.pop("api_keys", None)
        provider_cfg.pop("active_api_key_id", None)
        provider_cfg["api_key"] = ""

    return entries, active_id


def _safe_api_key_entries(entries: list[dict]) -> list[dict]:
    return [
        {
            "id": item["id"],
            "masked_key": _mask_secret(item.get("api_key", "")),
            "created_at": item.get("created_at"),
        }
        for item in entries
    ]


def _active_api_key(provider_cfg: dict) -> str:
    entries, active_id = _normalize_api_keys(provider_cfg)
    for item in entries:
        if item["id"] == active_id:
            return item["api_key"]
    return ""


def _set_active_api_key(provider_cfg: dict, key_id: str) -> str:
    entries, _ = _normalize_api_keys(provider_cfg)
    for item in entries:
        if item["id"] == key_id:
            provider_cfg["active_api_key_id"] = key_id
            provider_cfg["api_key"] = item["api_key"]
            return item["api_key"]
    raise ValueError("API Key 不存在或已被删除")


def _upsert_api_key(provider_cfg: dict, secret: str) -> str:
    value = secret.strip()
    if not value:
        return _normalize_api_keys(provider_cfg)[1] or ""

    entries, _ = _normalize_api_keys(provider_cfg)
    key_id = _secret_key_id(value)
    if not any(item["id"] == key_id for item in entries):
        entries.append(_api_key_entry(value, key_id=key_id))
    provider_cfg["api_keys"] = entries
    provider_cfg["active_api_key_id"] = key_id
    provider_cfg["api_key"] = value
    return key_id


def _resolve_api_key(provider_id: str, api_key: str = "", api_key_id: Optional[str] = None) -> str:
    if api_key.strip():
        return api_key.strip()
    cfg = load_config()
    provider_cfg = cfg.get("providers", {}).get(provider_id, {})
    if api_key_id:
        return _set_active_api_key(provider_cfg, api_key_id)
    return _active_api_key(provider_cfg)


# ── App ───────────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.active_provider = None
    app.state.active_provider_id = None
    app.state.active_model_id = None
    app.state.agent = JarvisAgent()
    app.state.heartbeat = HeartbeatEngine(app.state.agent.memory_manager)
    app.state.local_registry = LocalModelRegistry()
    app.state.model_downloads = {}
    app.state.assistant_sessions = {}

    # Auto-restore last active provider from disk
    cfg = load_config()
    pid = cfg.get("active_provider_id")
    mid = cfg.get("active_model_id")
    if pid and mid:
        try:
            if pid == "mlx_local":
                _ensure_mlx_dependency()
                provider, manifest = _create_local_provider(mid)
                app.state.active_provider = provider
                app.state.active_provider_id = "mlx_local"
                app.state.active_model_id = manifest["id"]
            else:
                pcfg = cfg.get("providers", {}).get(pid, {})
                provider = create_provider(pid, {
                    "api_key":        _active_api_key(pcfg),
                    "model":          mid,
                    "base_url":       pcfg.get("base_url"),
                    "aws_access_key": pcfg.get("aws_access_key"),
                    "aws_secret_key": pcfg.get("aws_secret_key"),
                    "region":         pcfg.get("region"),
                })
                app.state.active_provider = provider
                app.state.active_provider_id = pid
                app.state.active_model_id = mid
            logger.info("Restored provider: %s/%s", pid, mid)
        except Exception as e:
            logger.exception("Could not restore provider: %s", e)

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


@app.get("/memory", response_model=MemoryStatus)
async def memory_status():
    return MemoryStatus(**app.state.agent.memory_manager.memory_status())


@app.get("/memory/files", response_model=MemoryFilesResponse)
async def memory_files():
    return MemoryFilesResponse(files=app.state.agent.memory_manager.managed_files())


@app.put("/memory/files/{file_id}", response_model=MemoryFileUpdateResponse)
async def update_memory_file(file_id: str, req: MemoryFileUpdateRequest):
    try:
        file_payload = app.state.agent.memory_manager.update_managed_file(file_id, req.content)
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return MemoryFileUpdateResponse(file=file_payload)


def _preferences_response_payload() -> dict:
    status = app.state.agent.memory_manager.preferences_status()
    return {
        "preferences": {key: str(value) for key, value in status.get("preferences", {}).items()},
        "preference_meta": status.get("preference_meta", {}),
        "preference_stats": status.get("preference_stats", {}),
    }


@app.get("/memory/preferences", response_model=MemoryPreferencesResponse)
async def memory_preferences():
    return MemoryPreferencesResponse(**_preferences_response_payload())


@app.patch("/memory/preferences", response_model=MemoryPreferencesResponse)
async def update_memory_preferences(req: MemoryPreferencesPatch):
    values = req.model_dump(exclude_unset=True)
    app.state.agent.memory_manager.update_preferences(values, source="manual")
    return MemoryPreferencesResponse(**_preferences_response_payload())


@app.post("/memory/feedback", response_model=MemoryFeedbackResponse)
async def memory_feedback(req: MemoryFeedbackRequest):
    payload = req.model_dump(exclude_none=True)
    app.state.agent.memory_manager.append_learning(
        "candidate_feedback",
        payload,
    )
    app.state.agent.memory_manager.learn_from_candidate(
        req.action,
        payload.get("final_candidate"),
        req.session_id,
    )
    if req.session_id and req.action in {"accepted", "modified", "rejected", "skipped", "written", "replaced"}:
        app.state.agent.sessions.pop(req.session_id, None)
    return MemoryFeedbackResponse(status="ok")


def _assistant_sessions() -> dict:
    sessions = getattr(app.state, "assistant_sessions", None)
    if sessions is None:
        sessions = {}
        app.state.assistant_sessions = sessions
    return sessions


def _assistant_history(session_id: str) -> list[dict]:
    sessions = _assistant_sessions()
    history = sessions.setdefault(session_id, [])
    return history if isinstance(history, list) else []


def _append_assistant_message(session_id: str, role: str, content: str) -> None:
    history = _assistant_history(session_id)
    history.append({"role": role, "content": content})
    _assistant_sessions()[session_id] = history[-20:]


def _assistant_extraction_session_id(session_id: str) -> str:
    return f"assistant:{session_id}:{uuid4()}"


def _cron_tasks_reply() -> str:
    tasks = read_cron_tasks(app.state.agent.memory_manager)
    if not tasks:
        return "⏰ **Cron 弹窗提醒**\n\n当前没有任务。使用 `/cron-help` 查看命令。"

    lines = ["⏰ **已有 Cron 弹窗提醒**"]
    for idx, task in enumerate(tasks, start=1):
        lines.extend(
            [
                "",
                f"{idx}. **{task.title}**",
                f"   - **时间**：{describe_cron_expr(task.cron_expr)}",
                f"   - **ID**：`{task.id}`",
                f"   - **Cron**：`{task.cron_expr}`",
            ]
        )
        if task.body and task.body != task.title:
            lines.append(f"   - **说明**：{task.body}")
    return "\n".join(lines)


def _execute_memory_actions(plan) -> tuple[list[dict[str, str]], bool]:
    updates: list[dict[str, str]] = []
    requires_confirmation = False
    memory = app.state.agent.memory_manager

    for action in plan.memory_actions:
        if action.confidence < 0.6:
            requires_confirmation = True
            updates.append({"tool": action.tool, "status": "skipped_low_confidence"})
            continue

        args = action.arguments or {}
        if action.requires_confirmation and action.tool != "propose_soul_change":
            requires_confirmation = True
            updates.append({"tool": action.tool, "status": "needs_confirmation", **{k: str(v) for k, v in args.items()}})
            continue

        if action.tool == "set_user_profile":
            updates.append(memory.set_user_profile(args.get("field", ""), args.get("value", "")))
        elif action.tool == "append_user_memory":
            updates.append(memory.append_user_memory(args.get("category", ""), args.get("content", "")))
        elif action.tool == "update_schedule_preferences":
            status = memory.update_preferences(args, source="manual")
            updated = {
                key: str(value)
                for key, value in status.get("preferences", {}).items()
                if key in args
            }
            if updated:
                updates.append({"tool": "update_schedule_preferences", **updated})
            else:
                updates.append({"tool": "update_schedule_preferences", "status": "skipped_no_valid_fields"})
        elif action.tool == "propose_soul_change":
            requires_confirmation = True
            updates.append(memory.propose_soul_change(args.get("section", ""), args.get("proposal", "")))
        else:
            raise ValueError(f"unsupported memory tool: {action.tool}")

    return updates, requires_confirmation


async def _assistant_schedule_extraction_response(
    session_id: str,
    message: str,
    extraction_text: str,
    started: float,
) -> AssistantChatResponse:
    result = await app.state.agent.run(
        message=extraction_text,
        session_id=_assistant_extraction_session_id(session_id),
        input_mode="user_text",
        provider=app.state.active_provider,
    )
    agent_response = AgentResponse(**{k: v for k, v in result.items() if k in AgentResponse.model_fields})
    count = len(agent_response.candidates or [])
    if agent_response.type == "batch" and count > 0:
        reply = f"我识别到 {count} 项。"
        action = "review_candidates"
    else:
        reply = agent_response.reply or agent_response.error or "没有识别到可写入的日程或待办。"
        action = "chat"
    _append_assistant_message(session_id, "user", message)
    _append_assistant_message(session_id, "assistant", reply)
    logger.info(
        "POST /assistant/chat schedule action=%s count=%s elapsed=%.2fs",
        action,
        count,
        time.monotonic() - started,
    )
    return AssistantChatResponse(
        session_id=session_id,
        action=action,
        reply=reply,
        agent_response=agent_response if action == "review_candidates" else None,
    )


async def _assistant_plain_chat_response(
    session_id: str,
    message: str,
    started: float,
    log_label: str = "done",
) -> AssistantChatResponse:
    history = _assistant_history(session_id)
    messages = (history + [{"role": "user", "content": message}])[-20:]
    reply = await app.state.active_provider.chat(
        messages=messages,
        system_prompt=assistant_system_prompt(app.state.agent.memory_manager.render_prompt_context()),
    )
    reply = (reply or "").strip() or "我没有生成有效回复。"
    _append_assistant_message(session_id, "user", message)
    _append_assistant_message(session_id, "assistant", reply)
    logger.info("POST /assistant/chat %s session=%s elapsed=%.2fs", log_label, session_id, time.monotonic() - started)
    return AssistantChatResponse(session_id=session_id, action="chat", reply=reply)


@app.post("/assistant/chat", response_model=AssistantChatResponse)
async def assistant_chat(req: AssistantChatRequest):
    started = time.monotonic()
    session_id = req.session_id or str(uuid4())
    message = (req.message or "").strip()
    logger.info(
        "POST /assistant/chat session=%s message_chars=%s provider=%s model=%s",
        session_id,
        len(message),
        app.state.active_provider_id,
        app.state.active_model_id,
    )

    if not message:
        return AssistantChatResponse(
            session_id=session_id,
            action="chat",
            reply="请输入想说的内容。",
        )

    history = _assistant_history(session_id)
    if is_cron_help_request(message):
        reply = cron_help_text()
        _append_assistant_message(session_id, "user", message)
        _append_assistant_message(session_id, "assistant", reply)
        return AssistantChatResponse(session_id=session_id, action="chat", reply=reply)

    if is_cron_list_request(message):
        reply = _cron_tasks_reply()
        _append_assistant_message(session_id, "user", message)
        _append_assistant_message(session_id, "assistant", reply)
        return AssistantChatResponse(session_id=session_id, action="chat", reply=reply)

    if is_cron_delete_request(message):
        target_id = cron_delete_id(message)
        if not target_id:
            reply = "请使用 /cron-delete <cron-id> 删除 Cron 弹窗提醒。"
            action = "clarify"
        elif delete_cron_task(app.state.agent.memory_manager, target_id):
            reply = f"已删除 Cron 弹窗提醒：{target_id}。"
            action = "chat"
        else:
            reply = f"没有找到 Cron 弹窗提醒：{target_id}。可以用 /cron-list 查看现有任务。"
            action = "clarify"
        _append_assistant_message(session_id, "user", message)
        _append_assistant_message(session_id, "assistant", reply)
        return AssistantChatResponse(session_id=session_id, action=action, reply=reply)

    if is_cron_create_request(message):
        if not cron_command_payload(message):
            reply = cron_help_text()
            _append_assistant_message(session_id, "user", message)
            _append_assistant_message(session_id, "assistant", reply)
            return AssistantChatResponse(session_id=session_id, action="chat", reply=reply)

        if app.state.active_provider is None:
            return AssistantChatResponse(
                session_id=session_id,
                action="error",
                reply="解析 /cron 自然语言需要先配置云端 API 或加载本地 MLX 模型。",
                error="no_provider",
            )

        try:
            plan = await plan_cron_task(
                app.state.active_provider,
                message,
                datetime.now().astimezone(),
                app.state.agent.memory_manager.render_prompt_context(),
            )
            task = append_cron_task(
                app.state.agent.memory_manager,
                plan["cron_expr"],
                plan["title"],
                plan.get("body", ""),
            )
            reply = (
                "⏰ **Cron 弹窗提醒已创建**\n\n"
                f"- **内容**：{task.title}\n"
                f"- **时间**：{describe_cron_expr(task.cron_expr)}\n"
                f"- **ID**：`{task.id}`\n"
                f"- **Cron**：`{task.cron_expr}`\n"
                f"- **存储**：已写入 `heartbeat.md`"
            )
            _append_assistant_message(session_id, "user", message)
            _append_assistant_message(session_id, "assistant", reply)
            logger.info("POST /assistant/chat cron created id=%s elapsed=%.2fs", task.id, time.monotonic() - started)
            return AssistantChatResponse(session_id=session_id, action="chat", reply=reply)
        except ValueError as exc:
            reply = f"没能创建 Cron 弹窗提醒：{exc}\n\n{cron_help_text()}"
            _append_assistant_message(session_id, "user", message)
            _append_assistant_message(session_id, "assistant", reply)
            return AssistantChatResponse(session_id=session_id, action="clarify", reply=reply)
        except Exception as exc:
            logger.exception("POST /assistant/chat cron failed session=%s", session_id)
            return AssistantChatResponse(
                session_id=session_id,
                action="error",
                reply="创建 Cron 弹窗提醒失败，请稍后重试。",
                error=str(exc),
            )

    if is_slash_list_request(message):
        plan = heuristic_action_plan(message, datetime.now().astimezone())
        if plan and plan.action == "list_items":
            reply = plan.reply or "我来查一下。"
            _append_assistant_message(session_id, "user", message)
            _append_assistant_message(session_id, "assistant", reply)
            logger.info("POST /assistant/chat slash-list elapsed=%.2fs", time.monotonic() - started)
            return AssistantChatResponse(
                session_id=session_id,
                action="list_items",
                reply=reply,
                action_plan=plan,
            )

        reply = "请告诉我要查看的时间范围，例如 /list 未来2天。"
        _append_assistant_message(session_id, "user", message)
        _append_assistant_message(session_id, "assistant", reply)
        return AssistantChatResponse(
            session_id=session_id,
            action="clarify",
            reply=reply,
        )

    if app.state.active_provider is None:
        return AssistantChatResponse(
            session_id=session_id,
            action="error",
            reply="请先在菜单栏配置云端 API 或加载本地 MLX 模型。",
            error="no_provider",
        )

    contextual_creation_text = contextual_schedule_creation_text(message, history)
    if is_schedule_creation_request(message) or contextual_creation_text:
        try:
            return await _assistant_schedule_extraction_response(
                session_id=session_id,
                message=message,
                extraction_text=contextual_creation_text or message,
                started=started,
            )
        except Exception as e:
            logger.exception("POST /assistant/chat schedule failed session=%s", session_id)
            return AssistantChatResponse(
                session_id=session_id,
                action="error",
                reply="识别日程/待办失败，请稍后重试。",
                error=str(e),
            )

    if (
        is_local_operation_request(message)
        or is_contextual_local_operation_request(message, history)
        or is_memory_update_request(message)
        or parse_preference_update(message) is not None
    ):
        try:
            plan = await plan_assistant_action(
                app.state.active_provider,
                message,
                history,
                datetime.now().astimezone(),
                app.state.agent.memory_manager.render_prompt_context(),
            )
            action = "chat"
            reply = plan.reply or "好的。"
            if plan.action == "list_items":
                action = "list_items"
                reply = plan.reply or "我来查一下。"
            elif plan.action == "update_alert":
                action = "execute_operation"
                reply = plan.reply or "我来找到这项并修改提醒时间。"
            elif plan.action in {"delete_items", "reschedule_item"}:
                action = "confirm_operation"
                reply = plan.reply or "我会先找到匹配项，确认后再操作。"
            elif plan.action == "clarify":
                action = "clarify"
                reply = plan.clarification_question or plan.reply or "我需要再确认一下。"
            elif plan.action == "create_candidates":
                try:
                    return await _assistant_schedule_extraction_response(
                        session_id=session_id,
                        message=message,
                        extraction_text=message,
                        started=started,
                    )
                except Exception as e:
                    logger.exception("POST /assistant/chat schedule plan extraction failed session=%s", session_id)
                    return AssistantChatResponse(
                        session_id=session_id,
                        action="error",
                        reply="识别日程/待办失败，请稍后重试。",
                        error=str(e),
                    )
            elif plan.action == "update_preference" and plan.preference_values:
                status = app.state.agent.memory_manager.update_preferences(plan.preference_values, source="manual")
                updated = {
                    key: str(value)
                    for key, value in status.get("preferences", {}).items()
                    if key in plan.preference_values
                }
                reply = plan.reply or preference_reply(plan.preference_values)
                if "Memory" not in reply and "memory" not in reply:
                    reply = f"{reply} 已写入 Memory。"
                _append_assistant_message(session_id, "user", message)
                _append_assistant_message(session_id, "assistant", reply)
                logger.info("POST /assistant/chat preference updated elapsed=%.2fs", time.monotonic() - started)
                return AssistantChatResponse(
                    session_id=session_id,
                    action="preference_updated",
                    reply=reply,
                    updated_preferences=updated,
                    action_plan=plan,
                )
            elif plan.action == "update_memory" and plan.memory_actions:
                updates, requires_confirmation = _execute_memory_actions(plan)
                actual_writes = [
                    item for item in updates
                    if item.get("status") not in {"skipped_low_confidence", "needs_confirmation", "skipped_no_valid_fields"}
                    and item.get("tool") != "propose_soul_change"
                ]
                if requires_confirmation:
                    action = "clarify"
                    reply = plan.reply or "这项 Memory 修改需要你确认后再写入。"
                    if not reply.endswith("。"):
                        reply += "。"
                    reply += " 我还没有修改 soul.md。"
                elif not actual_writes:
                    action = "clarify"
                    reply = "我没有写入 Memory：没有识别到可保存的有效字段。"
                else:
                    action = "chat"
                    reply = plan.reply or "已写入 Memory。"
                    if "Memory" not in reply and "memory" not in reply:
                        reply = f"{reply} 已写入 Memory。"
                _append_assistant_message(session_id, "user", message)
                _append_assistant_message(session_id, "assistant", reply)
                logger.info(
                    "POST /assistant/chat memory updated count=%s confirm=%s elapsed=%.2fs",
                    len(updates),
                    requires_confirmation,
                    time.monotonic() - started,
                )
                return AssistantChatResponse(
                    session_id=session_id,
                    action=action,
                    reply=reply,
                    action_plan=plan,
                    memory_updates=updates,
                )

            if action == "review_candidates":
                # Let the existing extraction path handle creation so preference memory,
                # conflict status and multi-candidate review stay consistent.
                pass
            else:
                _append_assistant_message(session_id, "user", message)
                _append_assistant_message(session_id, "assistant", reply)
                logger.info(
                    "POST /assistant/chat plan action=%s plan=%s elapsed=%.2fs",
                    action,
                    plan.action,
                    time.monotonic() - started,
                )
                return AssistantChatResponse(
                    session_id=session_id,
                    action=action,
                    reply=reply,
                    action_plan=plan,
                )
        except Exception as e:
            logger.warning("POST /assistant/chat plan failed; falling back to chat session=%s error=%s", session_id, e)
            logger.debug("POST /assistant/chat plan fallback traceback session=%s", session_id, exc_info=True)
            try:
                return await _assistant_plain_chat_response(session_id, message, started, log_label="plan-fallback")
            except Exception as chat_exc:
                logger.exception("POST /assistant/chat plan fallback failed session=%s", session_id)
                return AssistantChatResponse(
                    session_id=session_id,
                    action="error",
                    reply="对话失败，请稍后重试。",
                    error=str(chat_exc),
                )

    try:
        return await _assistant_plain_chat_response(session_id, message, started)
    except Exception as e:
        logger.exception("POST /assistant/chat failed session=%s", session_id)
        return AssistantChatResponse(
            session_id=session_id,
            action="error",
            reply="对话失败，请稍后重试。",
            error=str(e),
        )


@app.post("/heartbeat/tick", response_model=HeartbeatTickResponse)
async def heartbeat_tick(req: HeartbeatTickRequest):
    try:
        return await app.state.heartbeat.tick(req)
    except Exception as e:
        logger.exception("heartbeat tick failed")
        app.state.agent.memory_manager.append_error("heartbeat_tick_failed", {"error": str(e)})
        return HeartbeatTickResponse(events=[])


def _model_supports_vision(provider_id: Optional[str], model_id: Optional[str]) -> bool:
    if not provider_id or not model_id:
        return False
    if provider_id == "mlx_local":
        return False
    cfg = PROVIDER_CONFIGS.get(provider_id, {})
    vision_models = cfg.get("vision_models", [])
    return model_id in vision_models


def _dependency_available(module_name: str) -> bool:
    return importlib.util.find_spec(module_name) is not None


def _ensure_mlx_dependency() -> None:
    if not _dependency_available("mlx_lm"):
        raise RuntimeError("未安装 mlx-lm，无法加载 MLX 本地模型")


def _registry() -> LocalModelRegistry:
    registry = getattr(app.state, "local_registry", None)
    if registry is None:
        registry = LocalModelRegistry()
        app.state.local_registry = registry
    return registry


def _download_state() -> dict:
    downloads = getattr(app.state, "model_downloads", None)
    if downloads is None:
        downloads = {}
        app.state.model_downloads = downloads
    return downloads


def _provider_display_name(provider_id: str) -> str:
    return PROVIDER_CONFIGS.get(provider_id, {}).get("display_name", provider_id)


def _cloud_source(provider_id: str, provider_cfg: dict) -> Optional[dict]:
    model_id = provider_cfg.get("model_id")
    if not provider_cfg.get("configured") or not model_id:
        return None
    provider_name = _provider_display_name(provider_id)
    return {
        "source": "cloud",
        "provider_id": provider_id,
        "model_id": model_id,
        "display_name": f"{provider_name} / {model_id}",
        "provider_display_name": provider_name,
        "supports_vision": _model_supports_vision(provider_id, model_id),
        "configured": True,
    }


def _local_source(manifest: dict) -> dict:
    display_name = manifest.get("display_name") or manifest.get("repo_id") or manifest.get("id")
    return {
        "source": "local",
        "provider_id": "mlx_local",
        "model_id": manifest.get("id"),
        "repo_id": manifest.get("repo_id"),
        "display_name": f"MLX / {display_name}",
        "provider_display_name": "MLX 本地",
        "supports_vision": False,
        "configured": True,
        "loaded": app.state.active_provider_id == "mlx_local" and app.state.active_model_id == manifest.get("id"),
    }


def _active_source_payload() -> Optional[dict]:
    pid = app.state.active_provider_id
    mid = app.state.active_model_id
    if not pid or not mid:
        return None
    if pid == "mlx_local":
        try:
            return _local_source(_registry().get_model(mid))
        except Exception:
            return {
                "source": "local",
                "provider_id": "mlx_local",
                "model_id": mid,
                "display_name": f"MLX / {mid}",
                "provider_display_name": "MLX 本地",
                "supports_vision": False,
                "configured": False,
                "loaded": False,
            }
    cfg = load_config()
    source = _cloud_source(pid, cfg.get("providers", {}).get(pid, {"model_id": mid, "configured": True}))
    return source


def _create_local_provider(model_id: str):
    manifest = _registry().get_model(model_id)
    provider = create_provider("mlx_local", {
        "model": manifest["id"],
        "model_path": manifest["local_path"],
        "display_name": manifest.get("display_name"),
    })
    return provider, manifest


@app.get("/config", response_model=GatewayConfig)
async def get_config():
    """Return current config (no API keys exposed)."""
    cfg = load_config()
    pid = cfg.get("active_provider_id")
    mid = cfg.get("active_model_id")
    providers_display = {}
    for p, pcfg in cfg.get("providers", {}).items():
        api_keys, active_api_key_id = _normalize_api_keys(pcfg)
        providers_display[p] = {
            "model_id":          pcfg.get("model_id"),
            "base_url":          pcfg.get("base_url"),
            "configured":        pcfg.get("configured", False),
            "api_keys":          _safe_api_key_entries(api_keys),
            "active_api_key_id": active_api_key_id,
        }
    return {
        "active_provider_id":    pid,
        "active_model_id":       mid,
        "active_model_vision":   _model_supports_vision(pid, mid),
        "providers":             providers_display,
    }


def _activate_cloud_model(provider_id: str, model_id: str) -> dict:
    cfg = load_config()
    provider_cfg = cfg.get("providers", {}).get(provider_id)
    if not provider_cfg or not provider_cfg.get("configured"):
        raise ValueError(f"Provider is not configured: {provider_id}")

    provider = create_provider(provider_id, {
        "api_key":        _active_api_key(provider_cfg),
        "model":          model_id,
        "base_url":       provider_cfg.get("base_url"),
        "aws_access_key": provider_cfg.get("aws_access_key"),
        "aws_secret_key": provider_cfg.get("aws_secret_key"),
        "region":         provider_cfg.get("region"),
    })

    app.state.active_provider = provider
    app.state.active_provider_id = provider_id
    app.state.active_model_id = model_id

    provider_cfg["model_id"] = model_id
    cfg.setdefault("providers", {})[provider_id] = provider_cfg
    cfg["active_provider_id"] = provider_id
    cfg["active_model_id"] = model_id
    save_config(cfg)
    return _cloud_source(provider_id, provider_cfg) or {}


def _build_local_provider(model_id: str):
    _ensure_mlx_dependency()
    return _create_local_provider(model_id)


def _set_active_local_model(provider, manifest: dict) -> None:
    app.state.active_provider = provider
    app.state.active_provider_id = "mlx_local"
    app.state.active_model_id = manifest["id"]

    cfg = load_config()
    cfg["active_provider_id"] = "mlx_local"
    cfg["active_model_id"] = manifest["id"]
    save_config(cfg)


def _activate_local_model(model_id: str):
    provider, manifest = _build_local_provider(model_id)
    _set_active_local_model(provider, manifest)
    return provider, manifest


@app.get("/models/available", response_model=AvailableModelsResponse)
async def available_models():
    """Return switchable inference sources without exposing secrets."""
    cfg = load_config()
    sources: list[dict] = []
    for provider_id, provider_cfg in cfg.get("providers", {}).items():
        source = _cloud_source(provider_id, provider_cfg)
        if source:
            sources.append(source)
    if _dependency_available("mlx_lm"):
        for manifest in _registry().list_models():
            sources.append(_local_source(manifest))
    return {
        "active": _active_source_payload(),
        "sources": sources,
        "mlx_available": _dependency_available("mlx_lm"),
        "models_dir": str(MODELS_DIR),
    }


@app.post("/models/activate", response_model=GatewayDetailResponse)
async def activate_model(req: ActivateModelRequest):
    """Switch the active inference source to a configured cloud model or installed MLX model."""
    try:
        if req.source == "cloud":
            if not req.provider_id:
                raise ValueError("provider_id is required for cloud source")
            source = _activate_cloud_model(req.provider_id, req.model_id)
        else:
            _, manifest = _activate_local_model(req.model_id)
            source = _local_source(manifest)
        return {"status": "ok", "active": source}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.get("/models", response_model=LocalModelsResponse)
async def models():
    """Return local MLX model manager state."""
    return {
        "models_dir": str(MODELS_DIR),
        "installed": _registry().list_models(),
        "recommended": RECOMMENDED_MLX_MODELS,
        "active_provider_id": app.state.active_provider_id,
        "active_model_id": app.state.active_model_id,
        "mlx_available": _dependency_available("mlx_lm"),
        "huggingface_hub_available": _dependency_available("huggingface_hub"),
        "downloads": list(_download_state().values()),
    }


@app.post("/models/download", response_model=ModelDownloadStatus)
async def download_model(req: ModelDownloadRequest):
    if not _dependency_available("huggingface_hub"):
        raise HTTPException(status_code=400, detail="未安装 huggingface_hub，无法下载 Hugging Face 模型")
    try:
        model_id = safe_model_id(req.repo_id)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

    downloads = _download_state()
    existing = downloads.get(model_id)
    if existing and existing.get("status") in {"queued", "downloading"}:
        return existing

    status = {
        "model_id": model_id,
        "repo_id": req.repo_id.strip(),
        "display_name": req.display_name.strip() if req.display_name else None,
        "revision": req.revision.strip() if req.revision else None,
        "status": "queued",
        "error": None,
        "local_path": str(_registry().model_path(model_id)),
    }
    downloads[model_id] = status
    asyncio.create_task(_download_model_task(status))
    return status


@app.get("/models/download/status", response_model=ModelDownloadStatusResponse)
async def download_status():
    return {"downloads": list(_download_state().values())}


@app.post("/models/load", response_model=GatewayDetailResponse)
async def load_model(req: ModelActionRequest):
    try:
        provider, manifest = _build_local_provider(req.model_id)
        await provider.verify()
        _set_active_local_model(provider, manifest)
        return {"status": "ok", "active": _local_source(manifest)}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.post("/models/unload", response_model=GatewayDetailResponse)
async def unload_model():
    if app.state.active_provider_id == "mlx_local":
        app.state.active_provider = None
        app.state.active_provider_id = None
        app.state.active_model_id = None
        cfg = load_config()
        cfg.pop("active_provider_id", None)
        cfg.pop("active_model_id", None)
        save_config(cfg)
    return {"status": "ok"}


@app.delete("/models/{model_id:path}", response_model=GatewayDetailResponse)
async def delete_model(model_id: str):
    try:
        safe_id = safe_model_id(model_id)
        if app.state.active_provider_id == "mlx_local" and app.state.active_model_id == safe_id:
            app.state.active_provider = None
            app.state.active_provider_id = None
            app.state.active_model_id = None
            cfg = load_config()
            cfg.pop("active_provider_id", None)
            cfg.pop("active_model_id", None)
            save_config(cfg)
        _registry().delete_model(safe_id)
        return {"status": "ok"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


async def _download_model_task(status: dict):
    status["status"] = "downloading"
    try:
        from huggingface_hub import snapshot_download

        registry = _registry()
        target = registry.model_path(status["model_id"])
        target.mkdir(parents=True, exist_ok=True)
        kwargs = {
            "repo_id": status["repo_id"],
            "local_dir": str(target),
        }
        if status.get("revision"):
            kwargs["revision"] = status["revision"]
        await asyncio.to_thread(snapshot_download, **kwargs)

        manifest = registry.build_manifest(
            repo_id=status["repo_id"],
            display_name=status.get("display_name"),
            revision=status.get("revision"),
        )
        registry.write_manifest(manifest)
        status["status"] = "complete"
        status["local_path"] = manifest["local_path"]
        status["error"] = None
    except Exception as e:
        logger.exception("Model download failed: %s", status.get("repo_id"))
        status["status"] = "failed"
        status["error"] = str(e)


@app.post("/settings", response_model=GatewayDetailResponse)
async def update_settings(req: SettingsRequest):
    """Save provider config to disk and activate it."""
    try:
        cfg = load_config()
        providers = cfg.get("providers", {})
        provider_cfg = providers.get(req.provider_id, {})

        if req.api_key.strip():
            _upsert_api_key(provider_cfg, req.api_key)
        elif req.api_key_id:
            _set_active_api_key(provider_cfg, req.api_key_id)
        else:
            _normalize_api_keys(provider_cfg)

        active_api_key = _active_api_key(provider_cfg)
        provider_cfg = {
            **provider_cfg,
            "model_id":       req.model_id,
            "base_url":       req.base_url,
            "aws_access_key": req.aws_access_key,
            "aws_secret_key": req.aws_secret_key,
            "region":         req.region,
            "configured":     True,
        }
        provider = create_provider(req.provider_id, {
            "api_key":        active_api_key,
            "model":          req.model_id,
            "base_url":       req.base_url,
            "aws_access_key": req.aws_access_key,
            "aws_secret_key": req.aws_secret_key,
            "region":         req.region,
        })

        app.state.active_provider    = provider
        app.state.active_provider_id = req.provider_id
        app.state.active_model_id    = req.model_id

        # Persist to disk
        cfg["active_provider_id"] = req.provider_id
        cfg["active_model_id"]    = req.model_id
        providers[req.provider_id] = provider_cfg
        cfg["providers"] = providers
        save_config(cfg)

        return {
            "status": "ok",
            "provider": req.provider_id,
            "model": req.model_id,
            "active_api_key_id": provider_cfg.get("active_api_key_id"),
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.post("/verify", response_model=VerifyResponse)
async def verify_provider(req: VerifyRequest):
    """Verify API key without saving to disk."""
    try:
        config = {
            "api_key":        _resolve_api_key(req.provider_id, req.api_key, req.api_key_id),
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


@app.post("/chat", response_model=AgentResponse)
async def chat(req: ChatRequest):
    started = time.monotonic()
    logger.info(
        "POST /chat session=%s input_mode=%s image=%s message_chars=%s provider=%s model=%s",
        req.session_id,
        req.input_mode,
        bool(req.image),
        len(req.message or ""),
        app.state.active_provider_id,
        app.state.active_model_id,
    )
    if app.state.active_provider is None:
        logger.warning("POST /chat no active provider")
        return AgentResponse(
            type="error",
            session_id=req.session_id,
            candidates=[],
            reply="请先在菜单栏配置云端 API 或加载本地 MLX 模型",
            error="no_provider",
        )
    try:
        result = await app.state.agent.run(
            message=req.message,
            image_base64=req.image,
            session_id=req.session_id,
            input_mode=req.input_mode,
            provider=app.state.active_provider,
            form_data=req.form_data,
            user_action=req.user_action,
            original_result=req.original_result,
            corrections=req.corrections,
            selected_candidate_ids=req.selected_candidate_ids,
        )
        response = AgentResponse(**{k: v for k, v in result.items() if k in AgentResponse.model_fields})
        logger.info(
            "POST /chat done session=%s type=%s error=%s elapsed=%.2fs",
            req.session_id,
            response.type,
            response.error,
            time.monotonic() - started,
        )
        return response
    except Exception as e:
        logger.exception("POST /chat failed session=%s elapsed=%.2fs", req.session_id, time.monotonic() - started)
        return AgentResponse(type="error", session_id=req.session_id, candidates=[], reply="识别失败，请重试", error=str(e))


def _default_model(provider_id: str) -> str:
    cfg = PROVIDER_CONFIGS.get(provider_id, {})
    models = cfg.get("preset_models", [])
    return models[0] if models else ""


if __name__ == "__main__":
    import uvicorn
    logger.info("Starting Jarvis gateway on 127.0.0.1:8765 log=%s", LOG_PATH)
    uvicorn.run(app, host="127.0.0.1", port=8765, log_level="warning")
