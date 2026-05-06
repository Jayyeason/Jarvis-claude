import logging
import time
import anthropic
from typing import Optional
from .base import BaseProvider
from agent.result import normalize_tool_result


logger = logging.getLogger("provider.claude")


class ClaudeProvider(BaseProvider):
    def __init__(self, api_key: str, model: str = "claude-sonnet-4-5"):
        self.client = anthropic.AsyncAnthropic(api_key=api_key)
        self.model = model

    async def chat(
        self,
        messages: list[dict],
        image_base64: Optional[str] = None,
        system_prompt: Optional[str] = None,
    ) -> str:
        api_messages = self._build_messages(messages, image_base64)
        kwargs: dict = {"model": self.model, "max_tokens": 2048, "messages": api_messages}
        if system_prompt:
            kwargs["system"] = system_prompt
        response = await self.client.messages.create(**kwargs)
        return response.content[0].text

    async def chat_with_tools(
        self,
        messages: list[dict],
        image_base64: Optional[str] = None,
        system_prompt: Optional[str] = None,
        tools: Optional[list] = None,
        tools_openai: Optional[list] = None,
    ) -> dict:
        started = time.monotonic()
        logger.info("chat_with_tools start model=%s image=%s tools=%s", self.model, bool(image_base64), len(tools or []))
        api_messages = self._build_messages(messages, image_base64)
        kwargs: dict = {
            "model": self.model,
            "max_tokens": 2048,
            "messages": api_messages,
            "tools": tools or [],
            "tool_choice": {"type": "any"},
        }
        if system_prompt:
            kwargs["system"] = system_prompt
        response = await self.client.messages.create(**kwargs)
        logger.info("chat_with_tools response model=%s elapsed=%.2fs", self.model, time.monotonic() - started)
        for block in response.content:
            if block.type == "tool_use":
                logger.info("tool_use name=%s elapsed=%.2fs", block.name, time.monotonic() - started)
                return normalize_tool_result(block.name, block.input)
        logger.warning("no tool call elapsed=%.2fs", time.monotonic() - started)
        return {
            "type": "none",
            "calendar": None,
            "reminder": None,
            "reply": "无法识别",
            "error": "no_tool_call",
        }

    async def verify(self) -> list[str]:
        from anthropic import APIStatusError
        try:
            await self.client.messages.create(
                model=self.model,
                max_tokens=1,
                messages=[{"role": "user", "content": "hi"}],
            )
            from .provider_configs import PROVIDER_CONFIGS
            return PROVIDER_CONFIGS["anthropic"]["preset_models"]
        except APIStatusError as e:
            raise ValueError(f"API Key 无效: {e.message}") from e

    def _build_messages(self, messages, image_base64):
        content: list = []
        if image_base64:
            content.append({
                "type": "image",
                "source": {"type": "base64", "media_type": "image/jpeg", "data": image_base64},
            })
        last_user = next(
            (m["content"] for m in reversed(messages) if m["role"] == "user"), ""
        )
        if last_user:
            content.append({"type": "text", "text": last_user})
        if not content:
            content.append({"type": "text", "text": "请识别截图"})
        return [{"role": "user", "content": content}]
