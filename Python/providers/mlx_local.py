import asyncio
import json
import logging
from pathlib import Path
from typing import Optional

from agent.result import normalize_tool_result

from .base import BaseProvider


logger = logging.getLogger("provider.mlx_local")


class MLXLocalProvider(BaseProvider):
    def __init__(self, model_path: str, model_id: str, display_name: Optional[str] = None):
        self.model_path = Path(model_path).expanduser()
        self.model_id = model_id
        self.display_name = display_name or model_id
        self._model = None
        self._tokenizer = None
        self._generate = None

    async def verify(self) -> list[str]:
        await asyncio.to_thread(self._ensure_loaded)
        return [self.model_id]

    async def chat(
        self,
        messages: list[dict],
        image_base64: Optional[str] = None,
        system_prompt: Optional[str] = None,
    ) -> str:
        if image_base64:
            raise RuntimeError("当前 MLX 本地模型只支持 OCR 文本输入，不支持图片输入")
        return await asyncio.to_thread(self._generate_plain_response, messages, system_prompt)

    async def chat_with_tools(
        self,
        messages: list[dict],
        image_base64: Optional[str] = None,
        system_prompt: Optional[str] = None,
        tools: Optional[list] = None,
        tools_openai: Optional[list] = None,
    ) -> dict:
        if image_base64:
            raise RuntimeError("当前 MLX 本地模型只支持 OCR 文本输入，不支持图片输入")
        raw = await asyncio.to_thread(self._generate_tool_response, messages, system_prompt)
        logger.info("mlx local response chars=%s", len(raw))
        return self._parse_tool_result(raw)

    def _ensure_loaded(self) -> None:
        if self._model is not None and self._tokenizer is not None and self._generate is not None:
            return
        if not self.model_path.exists():
            raise FileNotFoundError(f"MLX model path does not exist: {self.model_path}")
        try:
            from mlx_lm import generate, load
        except ImportError as exc:
            raise RuntimeError("未安装 mlx-lm，请先在 Python 环境中安装 mlx-lm 后再加载本地模型") from exc
        self._model, self._tokenizer = load(str(self.model_path))
        self._generate = generate

    def _generate_text(self, prompt: str, max_tokens: int) -> str:
        self._ensure_loaded()
        assert self._generate is not None
        try:
            return self._generate(
                self._model,
                self._tokenizer,
                prompt=prompt,
                max_tokens=max_tokens,
                verbose=False,
            )
        except TypeError:
            return self._generate(
                self._model,
                self._tokenizer,
                prompt=prompt,
                max_tokens=max_tokens,
            )

    def _generate_plain_response(self, messages: list[dict], system_prompt: Optional[str]) -> str:
        prompt = self._build_plain_prompt(messages, system_prompt)
        return self._generate_text(prompt, 1024)

    def _generate_tool_response(self, messages: list[dict], system_prompt: Optional[str]) -> str:
        prompt = self._build_tool_prompt(messages, system_prompt)
        return self._generate_text(prompt, 1200)

    def _build_plain_prompt(self, messages: list[dict], system_prompt: Optional[str]) -> str:
        body = "\n".join(f"{m.get('role', 'user')}: {m.get('content', '')}" for m in messages)
        return self._format_chat_prompt(system_prompt or "", body)

    def _build_tool_prompt(self, messages: list[dict], system_prompt: Optional[str]) -> str:
        user_text = "\n".join(str(m.get("content", "")) for m in messages if m.get("role", "user") == "user")
        tool_instruction = """
你当前运行在本地 MLX 文本模型中，不能真正调用工具。
请把应调用的工具转换成一个 JSON 对象，并且只输出 JSON，不要 Markdown，不要解释。

可输出的 JSON 形状：
1. 一个或多个候选：
{"type":"batch","candidates":[{"id":"candidate_1","kind":"calendar","calendar":{"title":"...","start_time":"YYYY-MM-DDTHH:MM:SS","end_time":"YYYY-MM-DDTHH:MM:SS 或 null","is_all_day":false,"needs_duration":false,"location":null,"notes":null,"recurrence":null,"travel_time_minutes":null,"alert_minutes_before_start":10,"calendar_name":null,"url":null},"reminder":null,"confidence":0.8,"evidence":"原文证据","missing_fields":[],"clarification_question":null,"conflicts":[],"status":"ready"},{"id":"candidate_2","kind":"reminder","calendar":null,"reminder":{"title":"...","due_date":"YYYY-MM-DD 或 null","due_time":"HH:MM 或 null","recurrence":null,"alert_minutes_before_due":null,"list_name":"提醒事项","priority":"none","flagged":false,"location":null,"notes":null,"url":null},"confidence":0.8,"evidence":"原文证据","missing_fields":[],"clarification_question":null,"conflicts":[],"status":"ready"}],"reply":null,"error":null,"missing_fields":[],"prefilled":null}
2. 无事件：
{"type":"none","candidates":[],"reply":"截图中没有识别到日程或任务","error":null,"missing_fields":[],"prefilled":null}
"""
        return self._format_chat_prompt(f"{system_prompt or ''}\n\n{tool_instruction}", user_text)

    def _format_chat_prompt(self, system: str, user: str) -> str:
        self._ensure_loaded()
        messages = []
        if system:
            messages.append({"role": "system", "content": system})
        messages.append({"role": "user", "content": user})
        template = getattr(self._tokenizer, "apply_chat_template", None)
        if callable(template):
            try:
                return template(messages, tokenize=False, add_generation_prompt=True)
            except Exception:
                logger.debug("tokenizer chat template failed; falling back to plain prompt", exc_info=True)
        return f"{system}\n\n用户输入：\n{user}\n\nJSON:"

    def _parse_tool_result(self, raw: str) -> dict:
        text = _strip_code_fence(raw.strip())
        try:
            data = json.loads(text)
        except json.JSONDecodeError:
            obj = _extract_first_json_object(text)
            if not obj:
                return {
                    "type": "none",
                    "calendar": None,
                    "reminder": None,
                    "reply": "本地模型没有返回可解析结果",
                    "error": "local_parse_failed",
                }
            try:
                data = json.loads(obj)
            except json.JSONDecodeError:
                return {
                    "type": "none",
                    "calendar": None,
                    "reminder": None,
                    "reply": "本地模型没有返回可解析结果",
                    "error": "local_parse_failed",
                }

        if not isinstance(data, dict):
            return {
                "type": "none",
                "calendar": None,
                "reminder": None,
                "reply": "本地模型没有返回对象结果",
                "error": "local_parse_failed",
            }

        if "type" in data:
            return data

        tool_name = data.get("tool_name") or data.get("name")
        args = data.get("arguments") or data.get("args") or {}
        if isinstance(tool_name, str) and isinstance(args, dict):
            return normalize_tool_result(tool_name, args)

        return {
            "type": "none",
            "calendar": None,
            "reminder": None,
            "reply": "本地模型没有返回可识别的工具结果",
            "error": "local_parse_failed",
        }


def _strip_code_fence(text: str) -> str:
    if not text.startswith("```"):
        return text
    lines = text.splitlines()
    if lines and lines[0].startswith("```"):
        lines = lines[1:]
    if lines and lines[-1].strip() == "```":
        lines = lines[:-1]
    return "\n".join(lines).strip()


def _extract_first_json_object(text: str) -> Optional[str]:
    start = text.find("{")
    if start < 0:
        return None
    depth = 0
    in_string = False
    escaped = False
    for idx in range(start, len(text)):
        ch = text[idx]
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[start:idx + 1]
    return None
