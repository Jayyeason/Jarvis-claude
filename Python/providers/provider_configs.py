PROVIDER_CONFIGS = {
    "openai": {
        "display_name": "OpenAI",
        "base_url": "https://api.openai.com/v1",
        "fields": ["api_key"],
        "preset_models": ["gpt-4o", "gpt-4o-mini"],
        "vision_models": ["gpt-4o", "gpt-4o-mini"],
    },
    "anthropic": {
        "display_name": "Anthropic",
        "fields": ["api_key"],
        "preset_models": ["claude-sonnet-4-5", "claude-haiku-4-5", "claude-opus-4-6"],
        "vision_models": ["claude-sonnet-4-5", "claude-haiku-4-5", "claude-opus-4-6"],
        "use_sdk": True,
    },
    "google": {
        "display_name": "Google Gemini",
        "base_url": "https://generativelanguage.googleapis.com/v1beta/openai",
        "fields": ["api_key"],
        "preset_models": ["gemini-2.0-flash", "gemini-1.5-pro"],
        "vision_models": ["gemini-2.0-flash", "gemini-1.5-pro"],
    },
    "deepseek": {
        "display_name": "DeepSeek",
        "base_url": "https://api.deepseek.com/v1",
        "fields": ["api_key"],
        "preset_models": ["deepseek-chat", "deepseek-reasoner"],
    },
    "openrouter": {
        "display_name": "OpenRouter",
        "base_url": "https://openrouter.ai/api/v1",
        "fields": ["api_key"],
        "fetch_models_from_api": True,
    },
    "moonshot": {
        "display_name": "Moonshot（月之暗面）",
        "base_url": "https://api.moonshot.cn/v1",
        "fields": ["api_key"],
        "preset_models": ["moonshot-v1-8k", "moonshot-v1-32k", "moonshot-v1-128k"],
    },
    "minimax": {
        "display_name": "MiniMax",
        "base_url": "https://api.minimax.chat/v1",
        "fields": ["api_key"],
        "preset_models": ["MiniMax-Text-01", "abab6.5s-chat"],
    },
    "glm": {
        "display_name": "GLM（智谱）",
        "base_url": "https://open.bigmodel.cn/api/paas/v4",
        "fields": ["api_key"],
        "preset_models": ["glm-4-plus", "glm-4-0520", "glm-4v-plus"],
        "vision_models": ["glm-4v-plus"],
    },
    "zai": {
        "display_name": "Z.AI",
        "base_url": "https://api.z.ai/api/paas/v4",
        "fields": ["api_key"],
        "preset_models": ["glm-4-plus", "glm-4v-plus"],
    },
    "bedrock": {
        "display_name": "Amazon Bedrock",
        "fields": ["aws_access_key", "aws_secret_key", "region"],
        "preset_models": ["anthropic.claude-sonnet-4-5-20251001-v2:0"],
        "note": "需要 AWS IAM 凭证，使用 boto3 SDK",
    },
    "vercel": {
        "display_name": "Vercel AI Gateway",
        "fields": ["api_key", "base_url"],
        "fetch_models_from_api": True,
    },
    "synthetic": {
        "display_name": "Synthetic",
        "base_url": "https://api.synthetic.new/v1",
        "fields": ["api_key"],
        "fetch_models_from_api": True,
    },
    "opencode_zen": {
        "display_name": "OpenCode Zen",
        "base_url": "https://api.opencode.zen/v1",
        "fields": ["api_key"],
    },
    "ollama": {
        "display_name": "Ollama（本地服务）",
        "base_url_default": "http://localhost:11434",
        "fields": ["base_url"],
        "fetch_models_endpoint": "/api/tags",
    },
    "custom": {
        "display_name": "自定义端点",
        "fields": ["base_url", "api_key", "model_id"],
    },
}

PROVIDER_DISPLAY_NAMES = {k: v["display_name"] for k, v in PROVIDER_CONFIGS.items()}
