from typing import Optional
from .base import BaseProvider
from .claude import ClaudeProvider
from .openai_compat import OpenAICompatProvider, OllamaProvider
from .provider_configs import PROVIDER_CONFIGS


def create_provider(provider_id: str, config: dict) -> BaseProvider:
    api_key = config.get("api_key", "")
    model = config.get("model", "")
    base_url = config.get("base_url")

    if provider_id == "anthropic":
        return ClaudeProvider(api_key=api_key, model=model or "claude-sonnet-4-5")

    if provider_id == "ollama":
        url = base_url or "http://localhost:11434"
        return OllamaProvider(base_url=url, model=model or "llama3.2")

    if provider_id == "bedrock":
        # Bedrock needs boto3 — lazy import to avoid hard dependency
        from .bedrock import BedrockProvider
        return BedrockProvider(
            access_key=config.get("aws_access_key", ""),
            secret_key=config.get("aws_secret_key", ""),
            region=config.get("region", "us-east-1"),
            model=model,
        )

    cfg = PROVIDER_CONFIGS.get(provider_id, {})
    url = base_url or cfg.get("base_url", "")
    if not url:
        raise ValueError(f"Unknown provider or missing base_url: {provider_id}")

    return OpenAICompatProvider(api_key=api_key, base_url=url, model=model)
