import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Optional


DEFAULT_MEMORY_PATH = Path.home() / ".jarvis" / "memory.json"
LEGACY_PREFERENCES_PATH = Path.home() / ".jarvis" / "user_preferences.json"


@dataclass(frozen=True)
class UserPreferences:
    calendar_default_duration_minutes: int = 60
    calendar_default_alert_minutes: int = 10
    reminder_default_due_time: str = "09:00"
    reminder_default_priority_for_deadline: str = "none"
    calendar_default_name: str = ""
    reminder_default_list_name: str = "提醒事项"


class MemoryManager:
    def __init__(self, path: Optional[Path] = None):
        self.path = path or DEFAULT_MEMORY_PATH

    def load_preferences(self) -> UserPreferences:
        data = self._load_memory_data()
        if not data:
            return UserPreferences()

        preferences = data.get("preferences", data)
        if not isinstance(preferences, dict):
            return UserPreferences()

        defaults = asdict(UserPreferences())
        values: dict[str, Any] = {}
        for key, default_value in defaults.items():
            value = preferences.get(key, default_value)
            values[key] = value if isinstance(value, type(default_value)) else default_value
        return UserPreferences(**values)

    def _load_memory_data(self) -> dict[str, Any]:
        data = self._read_json(self.path)
        if data is not None:
            return data

        if self.path == DEFAULT_MEMORY_PATH:
            return self._read_json(LEGACY_PREFERENCES_PATH) or {}
        return {}

    def _read_json(self, path: Path) -> Optional[dict[str, Any]]:
        if not path.exists():
            return None
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return None

        return data if isinstance(data, dict) else None

    def render_prompt_context(self) -> str:
        prefs = self.load_preferences()
        lines = [
            "## 用户偏好",
            f"- 日程默认时长：{prefs.calendar_default_duration_minutes} 分钟",
            f"- 日程默认提醒：提前 {prefs.calendar_default_alert_minutes} 分钟",
            f"- 提醒默认到期时间：{prefs.reminder_default_due_time}",
            f"- 截止类提醒默认优先级：{prefs.reminder_default_priority_for_deadline}",
        ]
        if prefs.calendar_default_name:
            lines.append(f"- 默认日历名称：{prefs.calendar_default_name}")
        if prefs.reminder_default_list_name:
            lines.append(f"- 默认提醒列表名称：{prefs.reminder_default_list_name}")
        return "\n".join(lines)
