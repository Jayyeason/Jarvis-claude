import logging
import json
from copy import deepcopy
from typing import Optional
from uuid import uuid4

from providers.base import BaseProvider

from .memory import MemoryManager
from .prompts import build_system_prompt
from .tools import get_anthropic_tools, get_openai_tools
from .validator import AgentValidationError, validate_agent_result


logger = logging.getLogger("agent")

MAX_VALIDATION_ATTEMPTS = 3


class JarvisAgent:
    def __init__(self, memory_manager: Optional[MemoryManager] = None):
        self.memory_manager = memory_manager or MemoryManager()
        self.sessions: dict[str, dict] = {}

    async def run(
        self,
        message: str,
        image_base64: Optional[str] = None,
        session_id: Optional[str] = None,
        input_mode: str = "user_text",
        provider: Optional[BaseProvider] = None,
        form_data: Optional[dict[str, str]] = None,
        user_action: Optional[str] = None,
        original_result: Optional[dict[str, str]] = None,
        corrections: Optional[dict[str, str]] = None,
        selected_candidate_ids: Optional[list[str]] = None,
    ) -> dict:
        session_id = session_id or str(uuid4())

        if user_action:
            self._record_user_action(
                session_id=session_id,
                user_action=user_action,
                original_result=original_result,
                corrections=corrections,
                selected_candidate_ids=selected_candidate_ids,
            )
            if user_action in {"accepted", "rejected"}:
                self.sessions.pop(session_id, None)

        if provider is None:
            return {
                "type": "error",
                "session_id": session_id,
                "candidates": [],
                "reply": "请先配置 API",
                "error": "no_provider",
                "missing_fields": [],
                "prefilled": None,
            }

        pending_session = self.sessions.get(session_id)
        is_followup = bool(
            pending_session and self._has_followup_payload(message, form_data, corrections, selected_candidate_ids)
        )
        if is_followup:
            user_text = self._build_followup_message(
                pending_session,
                message,
                form_data=form_data,
                corrections=corrections,
                selected_candidate_ids=selected_candidate_ids,
            )
            image_base64 = None
            input_mode = "user_text"
        else:
            user_text = message or "请识别这张截图中的日程或任务信息"

        logger.info(
            "Agent run input_mode=%s image=%s message_chars=%s session=%s",
            input_mode,
            bool(image_base64),
            len(user_text),
            session_id,
        )

        validation_error: Optional[str] = None
        system_prompt = build_system_prompt(self.memory_manager, input_mode=input_mode)

        for attempt in range(1, MAX_VALIDATION_ATTEMPTS + 1):
            try:
                raw_result = await provider.chat_with_tools(
                    messages=[{"role": "user", "content": self._build_attempt_message(user_text, validation_error)}],
                    image_base64=image_base64,
                    system_prompt=system_prompt,
                    tools=get_anthropic_tools(),
                    tools_openai=get_openai_tools(),
                )
                result = validate_agent_result(raw_result)
                if is_followup and selected_candidate_ids:
                    result = self._merge_followup_result(pending_session, result, selected_candidate_ids)
                result["session_id"] = session_id
                self._remember_session(session_id, result)
                if attempt > 1:
                    logger.info("Agent validation recovered session=%s attempt=%s", session_id, attempt)
                return result
            except AgentValidationError as e:
                validation_error = str(e)
                logger.warning(
                    "Agent validation failed session=%s attempt=%s/%s error=%s",
                    session_id,
                    attempt,
                    MAX_VALIDATION_ATTEMPTS,
                    validation_error,
                )
            except Exception as e:
                logger.exception("Agent run failed session=%s", session_id)
                return {
                    "type": "error",
                    "session_id": session_id,
                    "candidates": [],
                    "reply": "识别失败，请重试",
                    "error": str(e),
                    "missing_fields": [],
                    "prefilled": None,
                }

        return {
            "type": "error",
            "session_id": session_id,
            "candidates": [],
            "reply": "识别结果格式无效，请重试",
            "error": f"validation_failed: {validation_error}",
            "missing_fields": [],
            "prefilled": None,
        }

    def _build_attempt_message(self, user_text: str, validation_error: Optional[str]) -> str:
        if not validation_error:
            return user_text
        return (
            f"{user_text}\n\n"
            "上一次工具调用结果无效，需要重新调用一个工具。\n"
            f"无效原因：{validation_error}\n"
            "请调用 extract_schedule_items 返回所有可写入候选项，或调用 no_event；"
            "不要编造输入中没有的信息。"
        )

    def _has_followup_payload(
        self,
        message: str,
        form_data: Optional[dict[str, str]],
        corrections: Optional[dict[str, str]],
        selected_candidate_ids: Optional[list[str]],
    ) -> bool:
        return bool(
            (message or "").strip()
            or form_data
            or corrections
            or selected_candidate_ids
        )

    def _build_followup_message(
        self,
        pending_session: dict,
        message: str,
        form_data: Optional[dict[str, str]],
        corrections: Optional[dict[str, str]],
        selected_candidate_ids: Optional[list[str]],
    ) -> str:
        event_contexts = pending_session.get("event_contexts") or self._event_contexts_from_result(
            pending_session.get("result") or {}
        )
        selected_ids = selected_candidate_ids or (list(event_contexts.keys()) if len(event_contexts) == 1 else [])
        selected_events = [
            deepcopy(event_contexts[candidate_id])
            for candidate_id in selected_ids
            if candidate_id in event_contexts
        ]
        payload = {
            "current_events": selected_events,
            "user_message": message or "",
            "form_data": form_data or {},
            "corrections": corrections or {},
            "selected_candidate_ids": selected_ids,
        }
        return (
            "这是单个日程/待办 event 的后续补充。\n"
            "current_events 只包含正在处理的 event；不要引用、重排、删除或改写其它 event；"
            "只返回 selected_candidate_ids 指定 event 的更新结果，通常 candidates 只包含一个候选项；"
            "必须保留当前 event 的 id、kind 和用户没有改动的字段，合并 user_message、form_data 和 corrections；"
            "如果仍缺少标题、时间、地点或时长，继续在 missing_fields 标记，status 设为 needs_input，并填写 clarification_question；"
            "如果信息已完整，status 设为 ready 并省略 clarification_question。不要写入系统。\n\n"
            + json.dumps(payload, ensure_ascii=False, sort_keys=True)
        )

    def _merge_followup_result(
        self,
        pending_session: dict,
        result: dict,
        selected_candidate_ids: list[str],
    ) -> dict:
        if result.get("type") != "batch" or not selected_candidate_ids:
            return result

        previous = deepcopy(pending_session.get("result") or {})
        previous_candidates = previous.get("candidates") or []
        incoming_candidates = deepcopy(result.get("candidates") or [])
        selected = set(selected_candidate_ids)

        if len(selected_candidate_ids) == 1 and len(incoming_candidates) == 1:
            incoming_candidates[0]["id"] = selected_candidate_ids[0]

        incoming_by_id = {
            candidate.get("id"): candidate
            for candidate in incoming_candidates
            if candidate.get("id") in selected
        }
        if not incoming_by_id:
            return result

        merged = deepcopy(previous)
        merged_candidates = []
        seen: set[str] = set()
        for candidate in previous_candidates:
            candidate_id = candidate.get("id")
            if candidate_id in incoming_by_id:
                merged_candidates.append(incoming_by_id[candidate_id])
                seen.add(candidate_id)
            else:
                merged_candidates.append(candidate)

        for candidate_id, candidate in incoming_by_id.items():
            if candidate_id not in seen:
                merged_candidates.append(candidate)

        merged["type"] = "batch"
        merged["candidates"] = merged_candidates
        merged["reply"] = result.get("reply")
        merged["error"] = result.get("error")
        merged["missing_fields"] = result.get("missing_fields") or []
        merged["prefilled"] = result.get("prefilled")
        return validate_agent_result(merged)

    def _remember_session(self, session_id: str, result: dict) -> None:
        if result.get("type") in {"none", "error"}:
            return
        self.sessions[session_id] = {
            "result": result,
            "event_contexts": self._event_contexts_from_result(result),
        }
        if len(self.sessions) > 50:
            for key in list(self.sessions.keys())[:-50]:
                self.sessions.pop(key, None)

    def _event_contexts_from_result(self, result: dict) -> dict[str, dict]:
        return {
            candidate.get("id"): deepcopy(candidate)
            for candidate in result.get("candidates") or []
            if candidate.get("id")
        }

    def _record_user_action(
        self,
        session_id: str,
        user_action: str,
        original_result: Optional[dict[str, str]],
        corrections: Optional[dict[str, str]],
        selected_candidate_ids: Optional[list[str]],
    ) -> None:
        self.memory_manager.append_learning(
            "agent_user_action",
            {
                "session_id": session_id,
                "action": user_action,
                "original_result": original_result or {},
                "corrections": corrections or {},
                "selected_candidate_ids": selected_candidate_ids or [],
            },
        )
