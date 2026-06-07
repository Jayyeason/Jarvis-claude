from __future__ import annotations

import re
from copy import deepcopy
from datetime import datetime, timedelta
from typing import Any, Optional

from .memory import MemoryManager


ALERT_NUMBER_PATTERN = r"(?:\d{1,4}|[零〇一二两三四五六七八九十百]+|半)"
EXPLICIT_ALERT_PATTERNS = [
    rf"提前\s*{ALERT_NUMBER_PATTERN}\s*(?:min|分钟|分|个小时|小时|h|hour)",
    rf"{ALERT_NUMBER_PATTERN}\s*(?:min|分钟|分|个小时|小时|h|hour)\s*前\s*提醒",
    r"不\s*提醒",
    r"无需\s*提醒",
]
TIME_OF_DAY_RE = re.compile(
    r"(?P<period>凌晨|早上|上午|中午|下午|晚上|夜里)?\s*"
    r"(?P<hour>\d{1,2}|[零〇一二两三四五六七八九十]+)\s*[点时]"
    r"\s*(?P<minute>半|[0-5]?\d\s*分?|[零〇一二两三四五六七八九十]+\s*分?)?"
)
COLON_TIME_RE = re.compile(r"(?<!\d)(?P<hour>[01]?\d|2[0-3])[:：](?P<minute>[0-5]\d)(?!\d)")


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
        self._apply_explicit_reminder_alert(candidate, payload, context)

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

    def _apply_explicit_reminder_alert(self, candidate: dict[str, Any], payload: dict[str, Any], context: str) -> None:
        explicit = self._explicit_alert_from_text(context)
        if not explicit:
            return

        minutes, target_time = explicit
        current = self._nonnegative_int(payload.get("alert_minutes_before_due"))
        if current is None:
            payload["alert_minutes_before_due"] = minutes
            self._record(
                candidate,
                "reminder.alert_minutes_before_due",
                str(minutes),
                "提前提醒",
                "explicit",
                f"已按原文设置为提前 {minutes} 分钟提醒。",
            )

        if not target_time:
            return

        current_due_time = self._payload_due_time(payload)
        shifted = self._shift_time(target_time, -minutes)
        if current_due_time in {"", shifted}:
            self._set_payload_due_time(payload, target_time)
            self._remove_missing(candidate, "time")
            self._record(
                candidate,
                "reminder.due_time",
                target_time,
                "到期时间",
                "explicit",
                f"已按原文保持到期时间为 {target_time}，提前提醒单独写入提醒属性。",
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

    def _explicit_alert_from_text(self, text: str) -> Optional[tuple[int, str | None]]:
        minutes = self._extract_alert_minutes(text)
        if minutes is None:
            return None
        return minutes, self._extract_target_time(text)

    def _extract_alert_minutes(self, text: str) -> Optional[int]:
        number = rf"(?P<number>{ALERT_NUMBER_PATTERN})"
        patterns = [
            rf"提前\s*{number}\s*(?P<unit>min|分钟|分|个小时|小时|h|hour)",
            rf"{number}\s*(?P<unit>min|分钟|分|个小时|小时|h|hour)\s*前\s*提醒",
        ]
        for pattern in patterns:
            match = re.search(pattern, text, flags=re.IGNORECASE)
            if not match:
                continue
            raw_number = match.group("number")
            value = self._parse_number(raw_number)
            if value is None:
                continue
            unit = match.group("unit").lower()
            if raw_number == "半" and unit in {"个小时", "小时", "h", "hour"}:
                return 30
            return value * 60 if unit in {"个小时", "小时", "h", "hour"} else value
        return None

    def _extract_target_time(self, text: str) -> Optional[str]:
        matches: list[tuple[int, int, str]] = []
        for match in COLON_TIME_RE.finditer(text):
            hour = int(match.group("hour"))
            minute = int(match.group("minute"))
            matches.append((match.start(), match.end(), f"{hour:02d}:{minute:02d}"))
        for match in TIME_OF_DAY_RE.finditer(text):
            parsed = self._time_match_value(match, text)
            if parsed:
                matches.append((match.start(), match.end(), parsed))
        if not matches:
            return None

        matches.sort(key=lambda item: item[0])
        alert_idx = text.find("提前")
        if alert_idx >= 0:
            before_alert = [item for item in matches if item[1] <= alert_idx]
            if before_alert:
                return before_alert[-1][2]

        remind_idx = text.find("提醒")
        if remind_idx >= 0:
            before_remind = [item for item in matches if item[1] <= remind_idx]
            if before_remind:
                return before_remind[-1][2]

        return matches[0][2]

    def _time_match_value(self, match: re.Match[str], text: str) -> Optional[str]:
        hour = self._parse_number(match.group("hour"))
        if hour is None or hour > 23:
            return None
        minute_text = (match.group("minute") or "").strip()
        minute = 0
        if minute_text == "半":
            minute = 30
        elif minute_text:
            minute = self._parse_number(minute_text.replace("分", "").strip()) or 0
        if minute > 59:
            return None

        period = match.group("period") or ""
        if (period in {"下午", "晚上", "夜里"} or (not period and "今晚" in text)) and hour < 12:
            hour += 12
        elif period == "中午" and hour < 11:
            hour += 12
        return f"{hour:02d}:{minute:02d}"

    def _parse_number(self, value: str) -> Optional[int]:
        text = re.sub(r"\s+", "", (value or "").strip())
        if not text:
            return None
        if text.isdigit():
            return int(text)
        if text == "半":
            return 30
        digits = {
            "零": 0,
            "〇": 0,
            "一": 1,
            "二": 2,
            "两": 2,
            "三": 3,
            "四": 4,
            "五": 5,
            "六": 6,
            "七": 7,
            "八": 8,
            "九": 9,
        }
        if text in digits:
            return digits[text]
        if text == "十":
            return 10
        if "十" in text:
            before, after = text.split("十", 1)
            tens = 1 if before == "" else digits.get(before)
            ones = 0 if after == "" else digits.get(after)
            if tens is None or ones is None:
                return None
            return tens * 10 + ones
        if text.endswith("百"):
            value = digits.get(text[:-1] or "一")
            return value * 100 if value is not None else None
        return None

    def _payload_due_time(self, payload: dict[str, Any]) -> str:
        due_time = self._time_value(payload.get("due_time"))
        if due_time:
            return due_time
        due_date = self._trimmed(payload.get("due_date"))
        if "T" not in due_date:
            return ""
        parsed = self._parse_datetime(due_date)
        return parsed.strftime("%H:%M") if parsed else ""

    def _set_payload_due_time(self, payload: dict[str, Any], due_time: str) -> None:
        due_date = self._trimmed(payload.get("due_date"))
        if "T" in due_date:
            parsed = self._parse_datetime(due_date)
            if parsed:
                payload["due_date"] = parsed.date().isoformat()
        payload["due_time"] = due_time

    def _shift_time(self, value: str, minutes: int) -> str:
        parsed = datetime.strptime(value, "%H:%M")
        return (parsed + timedelta(minutes=minutes)).strftime("%H:%M")

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
