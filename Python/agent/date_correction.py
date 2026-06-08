from __future__ import annotations

import re
from copy import deepcopy
from datetime import date, datetime, timedelta
from typing import Any, Optional


def apply_relative_date_corrections(
    result: dict[str, Any],
    input_text: str,
    now: Optional[datetime] = None,
) -> dict[str, Any]:
    """Correct stale model dates when the user used an unambiguous relative day."""
    target_date = _relative_target_date(input_text, now or datetime.now().astimezone())
    if target_date is None or result.get("type") != "batch":
        return result

    output = deepcopy(result)
    for candidate in output.get("candidates") or []:
        if not isinstance(candidate, dict):
            continue
        if candidate.get("kind") == "calendar":
            _correct_calendar_candidate(candidate, target_date)
        elif candidate.get("kind") == "reminder":
            _correct_reminder_candidate(candidate, target_date)
    return output


def _relative_target_date(text: str, now: datetime) -> Optional[date]:
    normalized = re.sub(r"\s+", "", text or "")
    if not normalized:
        return None

    base = now.date()
    if "大后天" in normalized:
        return base + timedelta(days=3)
    if "后天" in normalized:
        return base + timedelta(days=2)
    if "明天" in normalized or "明晚" in normalized:
        return base + timedelta(days=1)
    if "今天" in normalized or "今晚" in normalized:
        return base
    return _next_weekday_date(normalized, base)


def _next_weekday_date(text: str, base: date) -> Optional[date]:
    match = re.search(r"(?:(下周|下个周|下星期|下个星期)\s*)?(?:周|星期|礼拜)([一二三四五六日天])", text)
    if not match:
        return None

    weekday_map = {
        "一": 0,
        "二": 1,
        "三": 2,
        "四": 3,
        "五": 4,
        "六": 5,
        "日": 6,
        "天": 6,
    }
    target_weekday = weekday_map.get(match.group(2))
    if target_weekday is None:
        return None

    delta = (target_weekday - base.weekday()) % 7
    if match.group(1):
        delta += 7 if delta == 0 else 0
    elif delta == 0:
        delta = 7
    return base + timedelta(days=delta)


def _correct_calendar_candidate(candidate: dict[str, Any], target_date: date) -> None:
    payload = candidate.get("calendar")
    if not isinstance(payload, dict):
        return

    start_value = payload.get("start_time")
    end_value = payload.get("end_time")
    start_date = _date_prefix(start_value)
    end_date = _date_prefix(end_value)

    if isinstance(start_value, str) and start_date:
        payload["start_time"] = _replace_date_prefix(start_value, target_date)
    if isinstance(end_value, str) and end_date:
        end_target = target_date
        if start_date:
            end_target = target_date + (end_date - start_date)
        payload["end_time"] = _replace_date_prefix(end_value, end_target)


def _correct_reminder_candidate(candidate: dict[str, Any], target_date: date) -> None:
    payload = candidate.get("reminder")
    if not isinstance(payload, dict):
        return
    due_date = payload.get("due_date")
    if isinstance(due_date, str) and _date_prefix(due_date):
        payload["due_date"] = _replace_date_prefix(due_date, target_date)


def _date_prefix(value: Any) -> Optional[date]:
    if not isinstance(value, str):
        return None
    match = re.match(r"^(\d{4}-\d{2}-\d{2})(?:$|T|\s)", value.strip())
    if not match:
        return None
    try:
        return date.fromisoformat(match.group(1))
    except ValueError:
        return None


def _replace_date_prefix(value: str, target_date: date) -> str:
    return re.sub(r"^\d{4}-\d{2}-\d{2}", target_date.isoformat(), value.strip(), count=1)
