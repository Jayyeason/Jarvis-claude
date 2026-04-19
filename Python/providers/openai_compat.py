import httpx
from openai import AsyncOpenAI, APIError
from typing import Optional
from .base import BaseProvider


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
        api_messages = []
        if system_prompt:
            api_messages.append({"role": "system", "content": system_prompt})

        for m in messages[:-1]:
            api_messages.append(m)

        last_content: list | str
        if image_base64:
            last_content = [
                {
                    "type": "image_url",
                    "image_url": {"url": f"data:image/jpeg;base64,{image_base64}"},
                }
            ]
            if messages:
                last_user = next(
                    (m["content"] for m in reversed(messages) if m["role"] == "user"),
                    "",
                )
                if last_user:
                    last_content.insert(0, {"type": "text", "text": last_user})
        else:
            last_content = messages[-1]["content"] if messages else ""

        api_messages.append({"role": "user", "content": last_content})

        response = await self.client.chat.completions.create(
            model=self.model,
            messages=api_messages,
            max_tokens=2048,
        )
        return response.choices[0].message.content or ""

    async def verify(self) -> list[str]:
        try:
            models_resp = await self.client.models.list()
            return [m.id for m in models_resp.data]
        except Exception:
            # Fallback: try a minimal chat
            await self.client.chat.completions.create(
                model=self.model,
                messages=[{"role": "user", "content": "hi"}],
                max_tokens=1,
            )
            return [self.model]


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
