import json
import re
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional


JARVIS_DIR = Path.home() / ".jarvis"
DEFAULT_MEMORY_PATH = Path.home() / ".jarvis" / "memory.json"
LEGACY_PREFERENCES_PATH = Path.home() / ".jarvis" / "user_preferences.json"
MEMORY_FILES = ["soul.md", "user.md", "tools.md", "heartbeat.md", "learnings.md", "errors.md", "wal.jsonl"]
MEMORY_FILE_READ_LIMIT_BYTES = 256 * 1024
MEMORY_FILE_WRITE_LIMIT_BYTES = 256 * 1024
USER_PREFERENCES_HEADING = "## 日程与提醒事项偏好"
LEGACY_USER_PREFERENCES_HEADINGS = ["## 日历与提醒偏好"]
REMINDER_DEFAULT_DUE_TIME_LABEL = "提醒事项默认当天DDL"
REMINDER_DEFAULT_ALERT_LABEL = "提醒事项默认提前提醒时间"
USER_PROFILE_HEADING = "## 用户资料"
USER_LONG_TERM_MEMORY_HEADINGS = {
    "fact": "## 用户长期事实",
    "preference": "## 用户长期偏好",
    "style": "## 交流风格偏好",
}
USER_PROFILE_FIELDS = {
    "preferred_name": "称呼偏好",
    "city": "城市",
    "timezone": "时区",
    "locale": "语言地区",
}
MANAGED_MEMORY_FILES = {
    "soul": {"filename": "soul.md", "title": "soul.md", "editable": True},
    "user": {"filename": "user.md", "title": "user.md", "editable": True},
    "heartbeat": {"filename": "heartbeat.md", "title": "heartbeat.md", "editable": True},
}
MANAGED_MEMORY_FILE_ORDER = ["soul", "user", "heartbeat"]


@dataclass(frozen=True)
class UserPreferences:
    calendar_default_duration_minutes: int = 60
    calendar_default_alert_minutes: int = 10
    reminder_default_alert_minutes: int = 10
    reminder_default_due_time: str = "09:00"
    reminder_default_priority_for_deadline: str = "none"


PREFERENCE_TYPES: dict[str, type | tuple[type, ...]] = {
    "calendar_default_duration_minutes": int,
    "calendar_default_alert_minutes": int,
    "reminder_default_alert_minutes": int,
    "reminder_default_due_time": str,
    "reminder_default_priority_for_deadline": str,
}

LEARNABLE_PREFERENCES = {
    "calendar_default_duration_minutes",
    "calendar_default_alert_minutes",
    "reminder_default_alert_minutes",
    "reminder_default_due_time",
}

LEARN_MIN_COUNT = 3
LEARN_MIN_SESSIONS = 2


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
                "- 对话中信息完整的单项 Calendar / Reminders / Notes 写入由系统自动执行，不额外确认。\n"
                "- 信息不足时只追问缺失字段；用户补齐后自动写入。\n"
                "- 删除、批量修改、冲突写入和修改 Jarvis 核心边界仍需要用户确认。\n"
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

        preferences = self._preference_dict(data)
        if not isinstance(preferences, dict):
            return UserPreferences()

        defaults = asdict(UserPreferences())
        values: dict[str, Any] = {}
        for key, default_value in defaults.items():
            value = preferences.get(key, default_value)
            normalized = self._normalize_preference_value(key, value)
            values[key] = normalized if normalized is not None else default_value
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

    def explicit_preferences(self) -> dict[str, Any]:
        data = self._load_memory_data()
        preferences = self._preference_dict(data)
        if not isinstance(preferences, dict):
            return {}
        return {
            key: value
            for key, value in preferences.items()
            if key in PREFERENCE_TYPES and self._valid_preference_value(key, value)
        }

    def preference_source(self, key: str) -> str:
        data = self._load_memory_data()
        meta = data.get("preference_meta", {}) if isinstance(data, dict) else {}
        item = meta.get(key, {}) if isinstance(meta, dict) else {}
        source = item.get("source") if isinstance(item, dict) else None
        return source if source in {"manual", "learned", "legacy"} else "learned"

    def preferences_status(self) -> dict[str, Any]:
        data = self._load_memory_data()
        return {
            "preferences": self.explicit_preferences(),
            "preference_meta": data.get("preference_meta", {}) if isinstance(data, dict) else {},
            "preference_stats": data.get("preference_stats", {}) if isinstance(data, dict) else {},
        }

    def managed_files(self) -> list[dict[str, Any]]:
        self.ensure_files()
        return [self._managed_file_payload(file_id) for file_id in MANAGED_MEMORY_FILE_ORDER]

    def update_managed_file(self, file_id: str, content: str) -> dict[str, Any]:
        meta = self._managed_file_meta(file_id)
        if not meta["editable"]:
            raise PermissionError(f"{meta['filename']} is read-only")
        if not isinstance(content, str):
            raise ValueError("content must be a string")

        data = content.encode("utf-8")
        if len(data) > MEMORY_FILE_WRITE_LIMIT_BYTES:
            raise ValueError(f"content exceeds {MEMORY_FILE_WRITE_LIMIT_BYTES} bytes")

        self.ensure_files()
        path = self.directory / meta["filename"]
        tmp = path.with_name(f".{path.name}.tmp")
        tmp.write_bytes(data)
        tmp.replace(path)
        if file_id == "user":
            self._normalize_user_markdown()
        return self._managed_file_payload(file_id)

    def update_preferences(self, values: dict[str, Any], source: str = "manual") -> dict[str, Any]:
        data = self._normalized_memory_data()
        preferences = data.setdefault("preferences", {})
        meta = data.setdefault("preference_meta", {})
        now = datetime.now(timezone.utc).isoformat()

        for key, value in values.items():
            if key not in PREFERENCE_TYPES:
                continue
            if value is None or value == "":
                preferences.pop(key, None)
                meta[key] = {"source": source, "confidence": 0.0, "updated_at": now, "cleared": True}
                continue
            normalized = self._normalize_preference_value(key, value)
            if normalized is None:
                continue
            preferences[key] = normalized
            meta[key] = {
                "source": source,
                "confidence": 1.0 if source == "manual" else 0.85,
                "updated_at": now,
                "observations": 0,
            }

        self._write_memory_data(data)
        self._sync_user_preferences_markdown()
        self._normalize_user_markdown()
        return self.preferences_status()

    def set_user_profile(self, field: str, value: str) -> dict[str, str]:
        key = self._clean_memory_key(field)
        label = USER_PROFILE_FIELDS.get(key)
        if not label:
            raise ValueError(f"unsupported user profile field: {field}")

        cleaned_value = self._clean_memory_text(value, 120)
        if not cleaned_value:
            raise ValueError("memory value is empty")

        self.ensure_files()
        path = self.directory / "user.md"
        current = path.read_text(encoding="utf-8") if path.exists() else "# user.md\n"
        updated = self._set_markdown_kv(current, USER_PROFILE_HEADING, label, cleaned_value)
        updated = self._normalize_user_markdown_text(updated)
        path.write_text(updated, encoding="utf-8")
        return {"tool": "set_user_profile", "field": key, "label": label, "value": cleaned_value}

    def append_user_memory(self, category: str, content: str) -> dict[str, str]:
        key = self._clean_memory_key(category)
        heading = USER_LONG_TERM_MEMORY_HEADINGS.get(key)
        if not heading:
            raise ValueError(f"unsupported user memory category: {category}")

        cleaned_content = self._clean_memory_text(content, 240)
        if not cleaned_content:
            raise ValueError("memory content is empty")

        self.ensure_files()
        path = self.directory / "user.md"
        current = path.read_text(encoding="utf-8") if path.exists() else "# user.md\n"
        updated = self._append_markdown_bullet(current, heading, cleaned_content)
        updated = self._normalize_user_markdown_text(updated)
        path.write_text(updated, encoding="utf-8")
        return {"tool": "append_user_memory", "category": key, "heading": heading.lstrip("# "), "value": cleaned_content}

    def propose_soul_change(self, section: str, proposal: str) -> dict[str, str]:
        cleaned_section = self._clean_memory_text(section, 80) or "未指定"
        cleaned_proposal = self._clean_memory_text(proposal, 300)
        if not cleaned_proposal:
            raise ValueError("soul proposal is empty")
        return {
            "tool": "propose_soul_change",
            "section": cleaned_section,
            "proposal": cleaned_proposal,
            "requires_confirmation": "true",
        }

    def learn_from_candidate(self, action: str, candidate: Optional[dict[str, Any]], session_id: Optional[str]) -> None:
        if action not in {"accepted", "modified", "written", "replaced"} or not isinstance(candidate, dict):
            return

        observations = self._candidate_observations(candidate)
        if not observations:
            return

        data = self._normalized_memory_data()
        stats = data.setdefault("preference_stats", {})
        now = datetime.now(timezone.utc).isoformat()
        session_value = session_id or candidate.get("id") or "unknown"

        for key, value in observations.items():
            if key not in LEARNABLE_PREFERENCES:
                continue
            normalized = self._normalize_preference_value(key, value)
            if normalized is None:
                continue
            value_key = str(normalized)
            field_stats = stats.setdefault(key, {})
            item = field_stats.setdefault(value_key, {"count": 0, "sessions": [], "last_seen": None})
            item["count"] = int(item.get("count") or 0) + 1
            sessions = item.get("sessions") if isinstance(item.get("sessions"), list) else []
            if session_value not in sessions:
                sessions.append(session_value)
            item["sessions"] = sessions[-20:]
            item["last_seen"] = now
            self._maybe_promote_preference(data, key, normalized, item, now)

        self._write_memory_data(data)
        self._sync_user_preferences_markdown()

    def _candidate_observations(self, candidate: dict[str, Any]) -> dict[str, Any]:
        kind = candidate.get("kind")
        if kind == "calendar":
            payload = candidate.get("calendar") or {}
            observations: dict[str, Any] = {}
            alert = payload.get("alert_minutes_before_start")
            if isinstance(alert, int) and alert >= 0:
                observations["calendar_default_alert_minutes"] = alert
            duration = self._calendar_duration_minutes(payload)
            if duration is not None:
                observations["calendar_default_duration_minutes"] = duration
            return observations

        if kind == "reminder":
            payload = candidate.get("reminder") or {}
            observations = {}
            due_time = payload.get("due_time")
            if isinstance(due_time, str) and due_time.strip():
                observations["reminder_default_due_time"] = due_time.strip()[:5]
            alert = payload.get("alert_minutes_before_due")
            if isinstance(alert, int) and alert >= 0:
                observations["reminder_default_alert_minutes"] = alert
            return observations

        return {}

    def _maybe_promote_preference(
        self,
        data: dict[str, Any],
        key: str,
        value: Any,
        stat_item: dict[str, Any],
        now: str,
    ) -> None:
        preferences = data.setdefault("preferences", {})
        meta = data.setdefault("preference_meta", {})
        existing_meta = meta.get(key, {}) if isinstance(meta.get(key), dict) else {}
        if existing_meta.get("source") == "manual":
            return

        count = int(stat_item.get("count") or 0)
        sessions = stat_item.get("sessions") if isinstance(stat_item.get("sessions"), list) else []
        if count < LEARN_MIN_COUNT or len(set(sessions)) < LEARN_MIN_SESSIONS:
            return

        preferences[key] = value
        meta[key] = {
            "source": "learned",
            "confidence": min(0.95, 0.55 + count * 0.1),
            "observations": count,
            "updated_at": now,
        }

    def _calendar_duration_minutes(self, payload: dict[str, Any]) -> Optional[int]:
        if payload.get("is_all_day"):
            return None
        start = self._parse_datetime(payload.get("start_time"))
        end = self._parse_datetime(payload.get("end_time"))
        if not start or not end or end <= start:
            return None
        minutes = round((end - start).total_seconds() / 60)
        return minutes if minutes > 0 else None

    def _parse_datetime(self, value: Any) -> Optional[datetime]:
        if not isinstance(value, str) or not value.strip() or "T" not in value:
            return None
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).replace(tzinfo=None)
        except ValueError:
            return None

    def _preference_dict(self, data: dict[str, Any]) -> dict[str, Any]:
        if not isinstance(data, dict):
            return {}
        if isinstance(data.get("preferences"), dict):
            return data["preferences"]
        return {key: data[key] for key in PREFERENCE_TYPES if key in data}

    def _normalized_memory_data(self) -> dict[str, Any]:
        data = self._load_memory_data()
        if not isinstance(data, dict):
            data = {}
        if "preferences" not in data:
            legacy_preferences = self._preference_dict(data)
            if legacy_preferences:
                for key in legacy_preferences:
                    data.pop(key, None)
                data["preferences"] = legacy_preferences
                now = datetime.now(timezone.utc).isoformat()
                data.setdefault("preference_meta", {})
                for key in legacy_preferences:
                    data["preference_meta"].setdefault(
                        key,
                        {"source": "legacy", "confidence": 0.7, "updated_at": now, "observations": 0},
                    )
            else:
                data["preferences"] = {}
        data.setdefault("preference_meta", {})
        data.setdefault("preference_stats", {})
        return data

    def _write_memory_data(self, data: dict[str, Any]) -> None:
        self.ensure_files()
        self.path.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")

    def _sync_user_preferences_markdown(self) -> None:
        self.ensure_files()
        path = self.directory / "user.md"
        current = path.read_text(encoding="utf-8") if path.exists() else "# user.md\n"
        updated = self._replace_or_append_section(
            current,
            [USER_PREFERENCES_HEADING, *LEGACY_USER_PREFERENCES_HEADINGS],
            self._user_preferences_section(),
        )
        path.write_text(updated, encoding="utf-8")

    def _replace_or_append_section(self, text: str, headings: str | list[str], section: str) -> str:
        heading_values = {headings} if isinstance(headings, str) else set(headings)
        lines = text.splitlines()
        section_lines = section.rstrip().splitlines()
        ranges: list[tuple[int, int]] = []
        idx = 0
        while idx < len(lines):
            if lines[idx].strip() not in heading_values:
                idx += 1
                continue

            start = idx
            end = len(lines)
            for next_idx in range(start + 1, len(lines)):
                stripped = lines[next_idx].lstrip()
                if stripped.startswith("## ") and not stripped.startswith("### "):
                    end = next_idx
                    break
            ranges.append((start, end))
            idx = end

        if not ranges:
            prefix = text.rstrip()
            return (prefix + "\n\n" if prefix else "") + "\n".join(section_lines) + "\n"

        updated: list[str] = []
        cursor = 0
        for range_idx, (start, end) in enumerate(ranges):
            updated.extend(lines[cursor:start])
            if range_idx == 0:
                updated.extend(section_lines)
            cursor = end
        updated.extend(lines[cursor:])
        return "\n".join(updated).rstrip() + "\n"

    def _set_markdown_kv(self, text: str, heading: str, label: str, value: str) -> str:
        lines = self._ensure_markdown_section(text, heading)
        start, end = self._section_range(lines, heading)
        target_prefix = f"- {label}："
        replacement = f"{target_prefix}{value}"
        for idx in range(start + 1, end):
            if lines[idx].strip().startswith(target_prefix):
                lines[idx] = replacement
                return "\n".join(lines).rstrip() + "\n"

        insert_at = end
        while insert_at > start + 1 and not lines[insert_at - 1].strip():
            insert_at -= 1
        lines.insert(insert_at, replacement)
        return "\n".join(lines).rstrip() + "\n"

    def _normalize_user_markdown(self) -> None:
        path = self.directory / "user.md"
        if not path.exists():
            return
        current = path.read_text(encoding="utf-8")
        updated = self._normalize_user_markdown_text(current)
        if updated != current:
            path.write_text(updated, encoding="utf-8")

    def _normalize_user_markdown_text(self, text: str) -> str:
        city = self._first_markdown_bullet(text, "## 城市")
        current_city = self._markdown_kv_value(text, USER_PROFILE_HEADING, USER_PROFILE_FIELDS["city"])
        updated = text
        if city and (not current_city or current_city == "auto"):
            updated = self._set_markdown_kv(updated, USER_PROFILE_HEADING, USER_PROFILE_FIELDS["city"], city)
        updated = self._remove_markdown_sections(updated, ["## 城市"])
        updated = self._replace_legacy_preference_labels(updated)
        return updated

    def _replace_legacy_preference_labels(self, text: str) -> str:
        replacements = {
            "- 提醒默认到期时间：": f"- {REMINDER_DEFAULT_DUE_TIME_LABEL}：",
            "- 提醒默认提前提醒：": f"- {REMINDER_DEFAULT_ALERT_LABEL}：",
        }
        updated = text
        for old, new in replacements.items():
            updated = updated.replace(old, new)
        return updated

    def _markdown_kv_value(self, text: str, heading: str, label: str) -> Optional[str]:
        lines = text.splitlines()
        if not any(line.strip() == heading for line in lines):
            return None
        start, end = self._section_range(lines, heading)
        target_prefix = f"- {label}："
        for idx in range(start + 1, end):
            stripped = lines[idx].strip()
            if stripped.startswith(target_prefix):
                value = stripped[len(target_prefix):].strip()
                return value or None
        return None

    def _first_markdown_bullet(self, text: str, heading: str) -> Optional[str]:
        lines = text.splitlines()
        if not any(line.strip() == heading for line in lines):
            return None
        start, end = self._section_range(lines, heading)
        for idx in range(start + 1, end):
            stripped = lines[idx].strip()
            if stripped.startswith("- "):
                value = stripped[2:].strip()
                return value or None
        return None

    def _remove_markdown_sections(self, text: str, headings: list[str]) -> str:
        heading_values = set(headings)
        lines = text.splitlines()
        updated: list[str] = []
        idx = 0
        while idx < len(lines):
            if lines[idx].strip() not in heading_values:
                updated.append(lines[idx])
                idx += 1
                continue

            idx += 1
            while idx < len(lines):
                stripped = lines[idx].lstrip()
                if stripped.startswith("## ") and not stripped.startswith("### "):
                    break
                idx += 1

            while updated and not updated[-1].strip():
                updated.pop()
            if idx < len(lines) and updated:
                updated.append("")

        return "\n".join(updated).rstrip() + "\n"

    def _append_markdown_bullet(self, text: str, heading: str, content: str) -> str:
        lines = self._ensure_markdown_section(text, heading)
        start, end = self._section_range(lines, heading)
        bullet = f"- {content}"
        for idx in range(start + 1, end):
            if lines[idx].strip() == bullet:
                return "\n".join(lines).rstrip() + "\n"

        insert_at = end
        while insert_at > start + 1 and not lines[insert_at - 1].strip():
            insert_at -= 1
        lines.insert(insert_at, bullet)
        return "\n".join(lines).rstrip() + "\n"

    def _ensure_markdown_section(self, text: str, heading: str) -> list[str]:
        base = (text or "# user.md\n").rstrip()
        if not base:
            base = "# user.md"
        lines = base.splitlines()
        if not any(line.strip() == heading for line in lines):
            if lines and lines[-1].strip():
                lines.extend(["", heading])
            else:
                lines.append(heading)
        return lines

    def _section_range(self, lines: list[str], heading: str) -> tuple[int, int]:
        start = next((idx for idx, line in enumerate(lines) if line.strip() == heading), None)
        if start is None:
            raise ValueError(f"missing section: {heading}")
        end = len(lines)
        for idx in range(start + 1, len(lines)):
            stripped = lines[idx].lstrip()
            if stripped.startswith("## ") and not stripped.startswith("### "):
                end = idx
                break
        return start, end

    def _normalize_preference_value(self, key: str, value: Any) -> Any:
        expected = PREFERENCE_TYPES.get(key)
        if expected is int:
            if isinstance(value, bool):
                return None
            if isinstance(value, int):
                return value if value >= 0 else None
            if isinstance(value, str) and value.strip().isdigit():
                return int(value.strip())
            return None
        if expected is str:
            if not isinstance(value, str):
                return None
            trimmed = value.strip()
            return trimmed or None
        return value

    def _valid_preference_value(self, key: str, value: Any) -> bool:
        if value is None:
            return key == "reminder_default_alert_minutes"
        normalized = self._normalize_preference_value(key, value)
        return normalized is not None

    def render_prompt_context(self) -> str:
        self._normalize_user_markdown()
        data = self._load_memory_data()
        preferences = data.get("preferences", data) if isinstance(data, dict) else {}
        prefs = self.load_preferences()
        reminder_due_time = (
            prefs.reminder_default_due_time
            if isinstance(preferences, dict) and "reminder_default_due_time" in preferences
            else "未学习稳定偏好，缺具体时间时追问用户"
        )
        reminder_alert = (
            f"提前 {prefs.reminder_default_alert_minutes} 分钟"
            if isinstance(preferences, dict) and "reminder_default_alert_minutes" in preferences
            and prefs.reminder_default_alert_minutes is not None
            else "未学习稳定偏好"
        )
        lines = [
            "## 用户偏好",
            f"- 日程默认时长：{prefs.calendar_default_duration_minutes} 分钟",
            f"- 日程默认提醒：提前 {prefs.calendar_default_alert_minutes} 分钟",
            f"- {REMINDER_DEFAULT_DUE_TIME_LABEL}：{reminder_due_time}",
            f"- {REMINDER_DEFAULT_ALERT_LABEL}：{reminder_alert}",
            f"- 截止类提醒默认优先级：{prefs.reminder_default_priority_for_deadline}",
        ]
        lines.append("- 写入容器：日程使用 macOS 系统默认日历；待办使用“提醒事项”列表")
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

    def _managed_file_meta(self, file_id: str) -> dict[str, Any]:
        meta = MANAGED_MEMORY_FILES.get(file_id)
        if not meta:
            raise ValueError(f"unknown memory file: {file_id}")
        return meta

    def _managed_file_payload(self, file_id: str) -> dict[str, Any]:
        meta = self._managed_file_meta(file_id)
        if file_id == "user":
            self._normalize_user_markdown()
        path = self.directory / meta["filename"]
        content, truncated, byte_size = self._read_managed_file(path)
        return {
            "id": file_id,
            "filename": meta["filename"],
            "title": meta["title"],
            "editable": meta["editable"],
            "content": content,
            "truncated": truncated,
            "byte_size": byte_size,
        }

    def _read_managed_file(self, path: Path) -> tuple[str, bool, int]:
        self.ensure_files()
        data = path.read_bytes() if path.exists() else b""
        byte_size = len(data)
        truncated = byte_size > MEMORY_FILE_READ_LIMIT_BYTES
        if truncated:
            data = data[-MEMORY_FILE_READ_LIMIT_BYTES:]
        return data.decode("utf-8", errors="replace"), truncated, byte_size

    def _default_user_markdown(self) -> str:
        return "# user.md\n\n" + self._user_preferences_section() + f"\n{USER_PROFILE_HEADING}\n- 城市：auto\n"

    def _user_preferences_section(self) -> str:
        data = self._load_memory_data()
        preferences = data.get("preferences", data) if isinstance(data, dict) else {}
        prefs = self.load_preferences() if data else UserPreferences()
        reminder_due_time = (
            prefs.reminder_default_due_time
            if isinstance(preferences, dict) and "reminder_default_due_time" in preferences
            else "未学习稳定偏好，缺具体时间时追问用户"
        )
        reminder_alert = (
            f"提前 {prefs.reminder_default_alert_minutes} 分钟"
            if isinstance(preferences, dict) and "reminder_default_alert_minutes" in preferences
            and prefs.reminder_default_alert_minutes is not None
            else "未学习稳定偏好"
        )
        return (
            f"{USER_PREFERENCES_HEADING}\n"
            f"- 日程默认时长：{prefs.calendar_default_duration_minutes} 分钟\n"
            f"- 日程默认提醒：提前 {prefs.calendar_default_alert_minutes} 分钟\n"
            f"- {REMINDER_DEFAULT_DUE_TIME_LABEL}：{reminder_due_time}\n"
            f"- {REMINDER_DEFAULT_ALERT_LABEL}：{reminder_alert}\n"
            "- 写入容器：日程使用 macOS 系统默认日历；待办使用“提醒事项”列表\n"
        )

    def _read_file(self, filename: str) -> str:
        path = self.directory / filename
        if not path.exists():
            return ""
        try:
            return path.read_text(encoding="utf-8")
        except Exception:
            return ""

    def _clean_memory_key(self, value: str) -> str:
        normalized = re.sub(r"[\s-]+", "_", (value or "").strip().lower())
        return re.sub(r"[^a-z_]", "", normalized)[:40]

    def _clean_memory_text(self, value: str, limit: int) -> str:
        text = re.sub(r"\s+", " ", (value or "").replace("\n", " ").strip())
        text = text.strip(" -。；;，,")
        return text[:limit]

    def _append_markdown_entry(self, filename: str, title: str, payload: dict[str, Any]) -> None:
        self.ensure_files()
        timestamp = datetime.now(timezone.utc).isoformat()
        body = json.dumps(payload, ensure_ascii=False, sort_keys=True)
        path = self.directory / filename
        with path.open("a", encoding="utf-8") as fh:
            fh.write(f"\n## {timestamp} | {title}\n{body}\n")

    def _truncate(self, text: str, limit: int) -> str:
        return text if len(text) <= limit else text[-limit:]
