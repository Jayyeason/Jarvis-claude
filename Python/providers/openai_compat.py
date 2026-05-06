import logging
import time
import httpx
from openai import AsyncOpenAI
from typing import Optional
from .base import BaseProvider
from agent.result import normalize_tool_result


logger = logging.getLogger("provider.openai_compat")


class OpenAICompatProvider(BaseProvider):
    def __init__(self, api_key: str, base_url: str, model: str):
        self.client = AsyncOpenAI(api_key=api_key or "ollama", base_url=base_url)
        self.model = model
        self.base_url = base_url

    async def chat(
        self,
        messages: list[dict],
        image_base64: Optional[str] = None,
        system_prompt: Optional[str] = None,
    ) -> str:
        api_messages = self._build_messages(messages, image_base64, system_prompt)
        response = await self.client.chat.completions.create(
            model=self.model,
            messages=api_messages,
            max_tokens=2048,
        )
        return response.choices[0].message.content or ""

    async def chat_with_tools(
        self,
        messages: list[dict],
        image_base64: Optional[str] = None,
        system_prompt: Optional[str] = None,
        tools: Optional[list] = None,
        tools_openai: Optional[list] = None,
    ) -> dict:
        started = time.monotonic()
        logger.info(
            "chat_with_tools start model=%s base_url=%s image=%s tools=%s",
            self.model,
            self.base_url,
            bool(image_base64),
            len(tools_openai or []),
        )
        api_messages = self._build_messages(messages, image_base64, system_prompt)
        response = await self.client.chat.completions.create(
            model=self.model,
            messages=api_messages,
            tools=tools_openai or [],
            tool_choice="required",
            max_tokens=2048,
        )
        logger.info("chat_with_tools response model=%s elapsed=%.2fs", self.model, time.monotonic() - started)
        msg = response.choices[0].message
        if msg.tool_calls:
            tc = msg.tool_calls[0]
            import json
            args = json.loads(tc.function.arguments)
            logger.info("tool_call name=%s elapsed=%.2fs", tc.function.name, time.monotonic() - started)
            return normalize_tool_result(tc.function.name, args)
        # Fallback: no tool call returned
        logger.warning("no tool call elapsed=%.2fs", time.monotonic() - started)
        return {
            "type": "none",
            "calendar": None,
            "reminder": None,
            "reply": msg.content or "无法识别",
            "error": "no_tool_call",
        }

    async def verify(self) -> list[str]:
        try:
            models_resp = await self.client.models.list()
            return [m.id for m in models_resp.data]
        except Exception:
            await self.client.chat.completions.create(
                model=self.model,
                messages=[{"role": "user", "content": "hi"}],
                max_tokens=1,
            )
            return [self.model]

    def _build_messages(self, messages, image_base64, system_prompt):
        api_messages = []
        if system_prompt:
            api_messages.append({"role": "system", "content": system_prompt})
        for m in messages[:-1]:
            api_messages.append(m)

        last = messages[-1] if messages else {"role": "user", "content": ""}
        if image_base64:
            content = []
            if last.get("content"):
                content.append({"type": "text", "text": last["content"]})
            content.append({
                "type": "image_url",
                "image_url": {"url": f"data:image/jpeg;base64,{image_base64}"},
            })
            api_messages.append({"role": "user", "content": content})
        else:
            api_messages.append(last)
        return api_messages


class OllamaProvider(OpenAICompatProvider):
    def __init__(self, base_url: str, model: str):
        super().__init__(api_key="ollama", base_url=f"{base_url}/v1", model=model)
        self.ollama_base = base_url

    async def verify(self) -> list[str]:
        async with httpx.AsyncClient() as client:
            resp = await client.get(f"{self.ollama_base}/api/tags", timeout=5)
            resp.raise_for_status()
            data = resp.json()
            return [m["name"] for m in data.get("models", [])]
