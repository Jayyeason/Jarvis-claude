from __future__ import annotations

import re
from copy import deepcopy
from datetime import datetime, timedelta
from typing import Any, Optional

from .memory import MemoryManager


EXPLICIT_ALERT_PATTERNS = [
    r"提前\s*\d+\s*(?:分钟|分|小时|h|hour)",
    r"\d+\s*(?:分钟|分|小时|h|hour)\s*前\s*提醒",
    r"不\s*提醒",
    r"无需\s*提醒",
]


class PreferenceEngine:
    def __init__(self, memory_manager: MemoryManager):
        self.memory_manager = memory_manager

    def apply(self, result: dict[str, Any], input_text: str = "") -> dict[str, Any]:
        if result.get("type") != "batch":
            return result

        explicit = self.memory_manager.explicit_preferences()
        prefs = self.memory_manager.load_preferences()
        effective = {
            "calendar_default_duration_minutes": prefs.calendar_default_duration_minutes,
            "calendar_default_alert_minutes": prefs.calendar_default_alert_minutes,
            "reminder_default_alert_minutes": prefs.reminder_default_alert_minutes,
            "reminder_default_due_time": prefs.reminder_default_due_time,
            **explicit,
        }

        output = deepcopy(result)
        for candidate in output.get("candidates") or []:
            candidate.setdefault("applied_preferences", [])
            context = " ".join(
                item
                for item in [
                    input_text,
                    str(candidate.get("evidence") or ""),
                    str((candidate.get("calendar") or {}).get("notes") or ""),
                    str((candidate.get("reminder") or {}).get("notes") or ""),
                ]
                if item
            )
            if candidate.get("kind") == "calendar":
                self._apply_calendar(candidate, effective, context, explicit_keys=set(explicit))
            elif candidate.get("kind") == "reminder":
                self._apply_reminder(candidate, effective, context, explicit_keys=set(explicit))
        return output

    def _apply_calendar(
        self,
        candidate: dict[str, Any],
        explicit: dict[str, Any],
        context: str,
        explicit_keys: set[str] | None = None,
    ) -> None:
        payload = candidate.get("calendar")
        if not isinstance(payload, dict):
            return
        explicit_keys = explicit_keys or set()

        if "calendar_default_duration_minutes" in explicit:
            minutes = self._positive_int(explicit.get("calendar_default_duration_minutes"))
            start = self._parse_datetime(payload.get("start_time"))
            end = self._parse_datetime(payload.get("end_time"))
            missing = set(candidate.get("missing_fields") or [])
            if minutes and start and not end and ("duration" in missing or payload.get("needs_duration")):
                end = start + timedelta(minutes=minutes)
                payload["end_time"] = self._format_datetime(end)
                payload["needs_duration"] = False
                self._remove_missing(candidate, "duration")
                self._record(
                    candidate,
                    "calendar.end_time",
                    self._format_datetime(end),
                    "时长",
                    self._source("calendar_default_duration_minutes", explicit_keys),
                    f"已设置为持续 {minutes} 分钟。",
                )

        if "calendar_default_alert_minutes" in explicit and not self._has_explicit_alert_text(context):
            minutes = self._nonnegative_int(explicit.get("calendar_default_alert_minutes"))
            current = payload.get("alert_minutes_before_start")
            if minutes is not None and (current is None or current == 10):
                payload["alert_minutes_before_start"] = minutes
                self._record(
                    candidate,
                    "calendar.alert_minutes_before_start",
                    str(minutes),
                    "提醒",
                    self._source("calendar_default_alert_minutes", explicit_keys),
                    f"已设置为提前 {minutes} 分钟提醒。",
                )

    def _apply_reminder(
        self,
        candidate: dict[str, Any],
        effective: dict[str, Any],
        context: str,
        explicit_keys: set[str] | None = None,
    ) -> None:
        payload = candidate.get("reminder")
        if not isinstance(payload, dict):
            return
        explicit_keys = explicit_keys or set()

        if "reminder_default_due_time" in effective:
            due_time = self._time_value(effective.get("reminder_default_due_time"))
            due_date = self._trimmed(payload.get("due_date"))
            current_due_time = self._trimmed(payload.get("due_time"))
            if due_time and due_date and "T" not in due_date and not current_due_time:
                payload["due_time"] = due_time
                self._remove_missing(candidate, "time")
                self._record(
                    candidate,
                    "reminder.due_time",
                    due_time,
                    "提醒时间",
                    self._source("reminder_default_due_time", explicit_keys),
                    f"已按你的偏好设置为 {due_time} 提醒，需要修改吗？",
                )

        if not self._has_explicit_alert_text(context):
            minutes = self._nonnegative_int(effective.get("reminder_default_alert_minutes"))
            current = payload.get("alert_minutes_before_due")
            if minutes is not None and current is None:
                payload["alert_minutes_before_due"] = minutes
                self._record(
                    candidate,
                    "reminder.alert_minutes_before_due",
                    str(minutes),
                    "提前提醒",
                    self._source("reminder_default_alert_minutes", explicit_keys),
                    f"已设置为提前 {minutes} 分钟提醒。",
                )

    def _record(
        self,
        candidate: dict[str, Any],
        field: str,
        value: str,
        label: str,
        source: str,
        message: str,
    ) -> None:
        applied = candidate.setdefault("applied_preferences", [])
        if any(item.get("field") == field for item in applied if isinstance(item, dict)):
            return
        applied.append(
            {
                "field": field,
                "value": value,
                "label": label,
                "source": source,
                "message": message,
            }
        )

    def _remove_missing(self, candidate: dict[str, Any], field: str) -> None:
        missing = candidate.get("missing_fields") or []
        candidate["missing_fields"] = [item for item in missing if item != field]

    def _source(self, key: str, explicit_keys: set[str] | None = None) -> str:
        if explicit_keys is not None and key not in explicit_keys:
            return "default"
        return self.memory_manager.preference_source(key)

    def _has_explicit_alert_text(self, text: str) -> bool:
        return any(re.search(pattern, text, flags=re.IGNORECASE) for pattern in EXPLICIT_ALERT_PATTERNS)

    def _parse_datetime(self, value: Any) -> Optional[datetime]:
        if not isinstance(value, str) or not value.strip() or "T" not in value:
            return None
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).replace(tzinfo=None)
        except ValueError:
            return None

    def _format_datetime(self, value: datetime) -> str:
        return value.isoformat(timespec="seconds")

    def _positive_int(self, value: Any) -> Optional[int]:
        parsed = self._nonnegative_int(value)
        return parsed if parsed and parsed > 0 else None

    def _nonnegative_int(self, value: Any) -> Optional[int]:
        if isinstance(value, bool):
            return None
        if isinstance(value, int) and value >= 0:
            return value
        if isinstance(value, str) and value.strip().isdigit():
            return int(value.strip())
        return None

    def _time_value(self, value: Any) -> Optional[str]:
        if not isinstance(value, str):
            return None
        trimmed = value.strip()
        if re.fullmatch(r"\d{1,2}:\d{2}", trimmed):
            hour, minute = trimmed.split(":")
            if 0 <= int(hour) <= 23 and 0 <= int(minute) <= 59:
                return f"{int(hour):02d}:{int(minute):02d}"
        return None

    def _trimmed(self, value: Any) -> str:
        return value.strip() if isinstance(value, str) else ""
