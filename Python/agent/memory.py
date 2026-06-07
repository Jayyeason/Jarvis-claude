import json
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional


JARVIS_DIR = Path.home() / ".jarvis"
DEFAULT_MEMORY_PATH = Path.home() / ".jarvis" / "memory.json"
LEGACY_PREFERENCES_PATH = Path.home() / ".jarvis" / "user_preferences.json"
MEMORY_FILES = ["soul.md", "user.md", "tools.md", "heartbeat.md", "learnings.md", "errors.md", "wal.jsonl"]


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
        self.directory = self.path.parent if path else JARVIS_DIR
        self.ensure_files()

    def ensure_files(self) -> None:
        self.directory.mkdir(parents=True, exist_ok=True)
        defaults = {
            "soul.md": (
                "# soul.md\n\n"
                "## Jarvis 核心边界\n"
                "- 所有写入 Calendar / Reminders 的操作必须由用户确认。\n"
                "- 主动触发时只提醒和建议，不自动写入。\n"
                "- 信息不足时标记缺失字段，让用户补充，不编造。\n\n"
                "## 语气风格\n"
                "语气：简洁直接\n"
            ),
            "user.md": self._default_user_markdown(),
            "tools.md": (
                "# tools.md\n\n"
                "## 工具规则\n"
                "- 截图可同时包含多个日程/待办，必须全部返回候选项。\n"
                "- 日程写入前需要检查冲突。\n"
                "- OCR 内容可能有噪声，不要补造缺失日期、时间或地点。\n"
            ),
            "heartbeat.md": (
                "# heartbeat.md\n\n"
                "## 每次 tick\n"
                "- 检查 30 分钟内日程。\n\n"
                "## 固定时间\n"
                "- 07:30 天气 + 外出安排\n"
                "- 18:00 今日到期未完成提醒\n"
                "- 21:00 明日重要事项准备\n\n"
                "## Cron 规则\n"
            ),
            "learnings.md": "# learnings.md\n",
            "errors.md": "# errors.md\n",
            "wal.jsonl": "",
        }
        for filename in MEMORY_FILES:
            path = self.directory / filename
            if not path.exists():
                path.write_text(defaults.get(filename, ""), encoding="utf-8")

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
        data = self._load_memory_data()
        preferences = data.get("preferences", data) if isinstance(data, dict) else {}
        prefs = self.load_preferences()
        reminder_due_time = (
            prefs.reminder_default_due_time
            if isinstance(preferences, dict) and "reminder_default_due_time" in preferences
            else "未学习稳定偏好，缺具体时间时追问用户"
        )
        lines = [
            "## 用户偏好",
            f"- 日程默认时长：{prefs.calendar_default_duration_minutes} 分钟",
            f"- 日程默认提醒：提前 {prefs.calendar_default_alert_minutes} 分钟",
            f"- 提醒默认到期时间：{reminder_due_time}",
            f"- 截止类提醒默认优先级：{prefs.reminder_default_priority_for_deadline}",
        ]
        if prefs.calendar_default_name:
            lines.append(f"- 默认日历名称：{prefs.calendar_default_name}")
        if prefs.reminder_default_list_name:
            lines.append(f"- 默认提醒列表名称：{prefs.reminder_default_list_name}")
        soul = self._read_file("soul.md").strip()
        user = self._read_file("user.md").strip()
        tools = self._read_file("tools.md").strip()
        if soul:
            lines.extend(["", "## Jarvis 边界", self._truncate(soul, 1200)])
        if user:
            lines.extend(["", "## 用户记忆", self._truncate(user, 1600)])
        if tools:
            lines.extend(["", "## 工具记忆", self._truncate(tools, 1000)])
        return "\n".join(lines)

    def append_learning(self, title: str, payload: dict[str, Any]) -> None:
        self._append_markdown_entry("learnings.md", title, payload)

    def append_error(self, title: str, payload: dict[str, Any]) -> None:
        self._append_markdown_entry("errors.md", title, payload)

    def memory_status(self) -> dict[str, Any]:
        return {
            "directory": str(self.directory),
            "files": {name: (self.directory / name).exists() for name in MEMORY_FILES},
            "prompt_context": self.render_prompt_context(),
            "recent_learnings": self.recent_entries("learnings.md", 10),
            "recent_errors": self.recent_entries("errors.md", 10),
        }

    def recent_entries(self, filename: str, max_entries: int) -> str:
        text = self._read_file(filename)
        chunks = text.split("\n## ")[1:]
        if not chunks:
            return ""
        return "\n## ".join(chunks[-max_entries:])

    def read_heartbeat_rules(self) -> str:
        return self._read_file("heartbeat.md")

    def _default_user_markdown(self) -> str:
        data = self._load_memory_data()
        preferences = data.get("preferences", data) if isinstance(data, dict) else {}
        prefs = self.load_preferences() if data else UserPreferences()
        reminder_due_time = (
            prefs.reminder_default_due_time
            if isinstance(preferences, dict) and "reminder_default_due_time" in preferences
            else "未学习稳定偏好，缺具体时间时追问用户"
        )
        return (
            "# user.md\n\n"
            "## 日历与提醒偏好\n"
            f"- 日程默认时长：{prefs.calendar_default_duration_minutes} 分钟\n"
            f"- 日程默认提醒：提前 {prefs.calendar_default_alert_minutes} 分钟\n"
            f"- 提醒默认到期时间：{reminder_due_time}\n"
            f"- 默认日历名称：{prefs.calendar_default_name or '系统默认'}\n"
            f"- 默认提醒列表：{prefs.reminder_default_list_name}\n\n"
            "## 城市\n"
            "- auto\n"
        )

    def _read_file(self, filename: str) -> str:
        path = self.directory / filename
        if not path.exists():
            return ""
        try:
            return path.read_text(encoding="utf-8")
        except Exception:
            return ""

    def _append_markdown_entry(self, filename: str, title: str, payload: dict[str, Any]) -> None:
        self.ensure_files()
        timestamp = datetime.now(timezone.utc).isoformat()
        body = json.dumps(payload, ensure_ascii=False, sort_keys=True)
        path = self.directory / filename
        with path.open("a", encoding="utf-8") as fh:
            fh.write(f"\n## {timestamp} | {title}\n{body}\n")

    def _truncate(self, text: str, limit: int) -> str:
        return text if len(text) <= limit else text[-limit:]
