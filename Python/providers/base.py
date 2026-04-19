from abc import ABC, abstractmethod
from typing import Optional


class BaseProvider(ABC):
    @abstractmethod
    async def chat(
        self,
        messages: list[dict],
        image_base64: Optional[str] = None,
        system_prompt: Optional[str] = None,
    ) -> str:
        pass

    @abstractmethod
    async def verify(self) -> list[str]:
        """Verify connectivity and return list of available model IDs."""
        pass
