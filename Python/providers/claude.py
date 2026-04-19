import anthropic
from typing import Optional
from .base import BaseProvider


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
        content: list = []
        if image_base64:
            content.append({
                "type": "image",
                "source": {
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": image_base64,
                },
            })
        if messages:
            last_user = next(
                (m["content"] for m in reversed(messages) if m["role"] == "user"),
                "",
            )
            if last_user:
                content.append({"type": "text", "text": last_user})

        if not content:
            content.append({"type": "text", "text": ""})

        api_messages = [{"role": "user", "content": content}]

        kwargs: dict = {
            "model": self.model,
            "max_tokens": 2048,
            "messages": api_messages,
        }
        if system_prompt:
            kwargs["system"] = system_prompt

        response = await self.client.messages.create(**kwargs)
        return response.content[0].text

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
