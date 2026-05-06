import logging
from typing import Optional

from providers.base import BaseProvider

from .memory import MemoryManager
from .prompts import build_system_prompt
from .tools import get_anthropic_tools, get_openai_tools


logger = logging.getLogger("agent")


class JarvisAgent:
    def __init__(self, memory_manager: Optional[MemoryManager] = None):
        self.memory_manager = memory_manager or MemoryManager()

    async def run(
        self,
        message: str,
        image_base64: Optional[str] = None,
        session_id: Optional[str] = None,
        input_mode: str = "user_text",
        provider: Optional[BaseProvider] = None,
    ) -> dict:
        if provider is None:
            return {
                "type": "error",
                "calendar": None,
                "reminder": None,
                "reply": "请先配置 API",
                "error": "no_provider",
            }

        user_text = message or "请识别这张截图中的日程或任务信息"

        try:
            logger.info(
                "Agent run input_mode=%s image=%s message_chars=%s session=%s",
                input_mode,
                bool(image_base64),
                len(user_text),
                session_id,
            )
            return await provider.chat_with_tools(
                messages=[{"role": "user", "content": user_text}],
                image_base64=image_base64,
                system_prompt=build_system_prompt(self.memory_manager, input_mode=input_mode),
                tools=get_anthropic_tools(),
                tools_openai=get_openai_tools(),
            )
        except Exception as e:
            logger.exception("Agent run failed session=%s", session_id)
            return {
                "type": "error",
                "calendar": None,
                "reminder": None,
                "reply": "识别失败，请重试",
                "error": str(e),
            }
