from __future__ import annotations

from copy import deepcopy
from datetime import date, datetime, time, timezone
from typing import Any


class AgentValidationError(ValueError):
    pass


VALID_TYPES = {"batch", "clarification", "calendar", "reminder", "none", "error"}
VALID_PRIORITIES = {"none", "low", "medium", "high"}
VALID_RECURRENCE_FREQUENCIES = {"daily", "weekly", "monthly", "yearly"}
VALID_WEEKDAYS = {
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "sunday",
}


def validate_agent_result(result: dict[str, Any]) -> dict[str, Any]:
    """Validate and lightly normalize the LLM tool result before it reaches Swift."""
    if not isinstance(result, dict):
        raise AgentValidationError("result must be an object")

    normalized = deepcopy(result)
    result_type = normalized.get("type")
    if result_type not in VALID_TYPES:
        raise AgentValidationError(f"unknown result type: {result_type}")

    if result_type == "batch":
        _validate_batch(normalized)
    elif result_type == "clarification":
        _validate_clarification(normalized)
    elif result_type == "calendar":
        _validate_calendar(normalized)
    elif result_type == "reminder":
        _validate_reminder(normalized)
    elif result_type == "none":
        _validate_none(normalized)
    else:
        normalized.setdefault("calendar", None)
        normalized.setdefault("reminder", None)
        normalized.setdefault("reply", "识别失败，请重试")
        normalized.setdefault("error", "agent_error")

    return normalized


def _validate_batch(result: dict[str, Any]) -> None:
    candidates = result.get("candidates")
    if not isinstance(candidates, list):
        raise AgentValidationError("batch result missing candidates list")

    normalized_candidates = []
    for idx, candidate in enumerate(candidates, start=1):
        if not isinstance(candidate, dict):
            raise AgentValidationError("candidate must be an object")
        kind = candidate.get("kind")
        if kind not in {"calendar", "reminder"}:
            raise AgentValidationError(f"invalid candidate kind: {kind}")
        candidate.setdefault("id", f"candidate_{idx}")
        candidate.setdefault("confidence", 0.8)
        candidate.setdefault("evidence", None)
        candidate.setdefault("missing_fields", [])
        candidate.setdefault("clarification_question", None)
        candidate.setdefault("conflicts", [])
        if kind == "calendar":
            _validate_calendar_candidate(candidate)
        else:
            _validate_reminder_candidate(candidate)
        normalized_candidates.append(candidate)

    if not normalized_candidates:
        result["type"] = "none"
        result["reply"] = result.get("reply") or "截图中没有识别到日程或任务"

    result["candidates"] = normalized_candidates
    result.setdefault("session_id", None)
    result.setdefault("reply", None)
    result.setdefault("error", None)
    result.setdefault("missing_fields", [])
    result.setdefault("prefilled", None)


def _validate_calendar_candidate(candidate: dict[str, Any]) -> None:
    payload = candidate.get("calendar")
    if not isinstance(payload, dict):
        raise AgentValidationError("calendar candidate missing calendar payload")

    missing = set(candidate.get("missing_fields") or [])
    title = payload.get("title")
    if not isinstance(title, str) or not title.strip():
        missing.add("title")

    start_value = payload.get("start_time")
    start_dt = None
    start_is_date_only = False
    is_all_day = bool(payload.get("is_all_day", False))
    if _is_blank(start_value):
        payload["start_time"] = None
        missing.add("time")
    elif not isinstance(start_value, str):
        raise AgentValidationError("calendar start_time must be a string")
    else:
        start_dt, start_is_date_only = _parse_date_or_datetime(start_value, "calendar start_time")
        if start_is_date_only and not is_all_day:
            missing.add("time")

    end_value = payload.get("end_time")
    if _is_blank(end_value):
        payload["end_time"] = None
        if not is_all_day:
            payload["needs_duration"] = True
            missing.add("duration")
    else:
        if not isinstance(end_value, str):
            raise AgentValidationError("calendar end_time must be a string")
        end_dt, end_is_date_only = _parse_date_or_datetime(end_value, "calendar end_time")
        if end_is_date_only and not is_all_day:
            payload["end_time"] = None
            payload["needs_duration"] = True
            missing.add("duration")
        elif start_dt is not None:
            if is_all_day:
                if end_dt < start_dt:
                    raise AgentValidationError("calendar end_time is before start_time")
            elif end_dt <= start_dt:
                raise AgentValidationError("calendar end_time must be after start_time")

    _validate_optional_nonnegative_int(payload, "alert_minutes_before_start")
    _validate_optional_nonnegative_int(payload, "travel_time_minutes")
    _validate_recurrence(payload.get("recurrence"))

    payload.setdefault("is_all_day", False)
    payload.setdefault("needs_duration", False)
    payload.setdefault("alert_minutes_before_start", 10)
    candidate["reminder"] = None
    _finish_candidate_status(candidate, sorted(missing))


def _validate_reminder_candidate(candidate: dict[str, Any]) -> None:
    payload = candidate.get("reminder")
    if not isinstance(payload, dict):
        raise AgentValidationError("reminder candidate missing reminder payload")

    missing = set(candidate.get("missing_fields") or [])
    title = payload.get("title")
    if not isinstance(title, str) or not title.strip():
        missing.add("title")

    due_date = payload.get("due_date")
    if not _is_blank(due_date):
        if not isinstance(due_date, str):
            raise AgentValidationError("reminder due_date must be a string")
        _parse_date_or_datetime(due_date, "reminder due_date")
    else:
        payload["due_date"] = None

    due_time = payload.get("due_time")
    if not _is_blank(due_time):
        if not isinstance(due_time, str):
            raise AgentValidationError("reminder due_time must be a string")
        _parse_time(due_time, "reminder due_time")
    else:
        payload["due_time"] = None

    priority = payload.get("priority", "none")
    if priority not in VALID_PRIORITIES:
        raise AgentValidationError(f"invalid reminder priority: {priority}")

    _validate_optional_nonnegative_int(payload, "alert_minutes_before_due")
    _validate_recurrence(payload.get("recurrence"))

    payload.setdefault("list_name", "提醒事项")
    payload.setdefault("priority", "none")
    payload.setdefault("flagged", False)
    candidate["calendar"] = None
    _finish_candidate_status(candidate, sorted(missing))


def _finish_candidate_status(candidate: dict[str, Any], missing: list[str]) -> None:
    candidate["missing_fields"] = missing
    question = candidate.get("clarification_question")
    if candidate.get("conflicts"):
        candidate["status"] = "conflict"
    elif missing:
        candidate["status"] = "needs_input"
        if not isinstance(question, str) or not question.strip():
            candidate["clarification_question"] = _fallback_clarification_question(candidate.get("kind"), missing)
    else:
        candidate["status"] = "ready"
        candidate["clarification_question"] = None


def _fallback_clarification_question(kind: str | None, missing: list[str]) -> str:
    missing_set = set(missing)
    parts: list[str] = []
    if "title" in missing_set:
        parts.append("标题是什么？")
    if "time" in missing_set:
        parts.append("几点开始？" if kind == "calendar" else "什么时候提醒？")
    if "duration" in missing_set:
        parts.append("预计持续多久？")
    if "location" in missing_set:
        parts.append("在哪里？")
    return "".join(parts) or "请补充这项信息。"


def _validate_clarification(result: dict[str, Any]) -> None:
    fields = result.get("missing_fields") or []
    if not isinstance(fields, list):
        raise AgentValidationError("clarification missing_fields must be a list")
    result.setdefault("candidates", [])
    result.setdefault("reply", "请补充缺失信息")
    result.setdefault("error", None)
    result.setdefault("prefilled", None)


def _validate_calendar(result: dict[str, Any]) -> None:
    payload = result.get("calendar")
    if not isinstance(payload, dict):
        raise AgentValidationError("calendar result missing calendar payload")

    title = payload.get("title")
    if not isinstance(title, str) or not title.strip():
        raise AgentValidationError("calendar title is required")

    start_value = payload.get("start_time")
    if not isinstance(start_value, str) or not start_value.strip():
        raise AgentValidationError("calendar start_time is required")

    start_dt, start_is_date_only = _parse_date_or_datetime(start_value, "calendar start_time")
    is_all_day = bool(payload.get("is_all_day", False))
    if start_is_date_only and not is_all_day:
        raise AgentValidationError("non-all-day calendar start_time must include a time")

    end_value = payload.get("end_time")
    if _is_blank(end_value):
        payload["end_time"] = None
        if not is_all_day:
            payload["needs_duration"] = True
    else:
        if not isinstance(end_value, str):
            raise AgentValidationError("calendar end_time must be a string")
        end_dt, end_is_date_only = _parse_date_or_datetime(end_value, "calendar end_time")
        if end_is_date_only and not is_all_day:
            raise AgentValidationError("non-all-day calendar end_time must include a time")
        if is_all_day:
            if end_dt < start_dt:
                raise AgentValidationError("calendar end_time is before start_time")
        elif end_dt <= start_dt:
            raise AgentValidationError("calendar end_time must be after start_time")

    _validate_optional_nonnegative_int(payload, "alert_minutes_before_start")
    _validate_optional_nonnegative_int(payload, "travel_time_minutes")
    _validate_recurrence(payload.get("recurrence"))

    payload.setdefault("is_all_day", False)
    payload.setdefault("needs_duration", False)
    payload.setdefault("alert_minutes_before_start", 10)
    result["reminder"] = None
    result.setdefault("reply", None)
    result.setdefault("error", None)


def _validate_reminder(result: dict[str, Any]) -> None:
    payload = result.get("reminder")
    if not isinstance(payload, dict):
        raise AgentValidationError("reminder result missing reminder payload")

    title = payload.get("title")
    if not isinstance(title, str) or not title.strip():
        raise AgentValidationError("reminder title is required")

    due_date = payload.get("due_date")
    if not _is_blank(due_date):
        if not isinstance(due_date, str):
            raise AgentValidationError("reminder due_date must be a string")
        _parse_date_or_datetime(due_date, "reminder due_date")
    else:
        payload["due_date"] = None

    due_time = payload.get("due_time")
    if not _is_blank(due_time):
        if not isinstance(due_time, str):
            raise AgentValidationError("reminder due_time must be a string")
        _parse_time(due_time, "reminder due_time")
    else:
        payload["due_time"] = None

    priority = payload.get("priority", "none")
    if priority not in VALID_PRIORITIES:
        raise AgentValidationError(f"invalid reminder priority: {priority}")

    _validate_optional_nonnegative_int(payload, "alert_minutes_before_due")
    _validate_recurrence(payload.get("recurrence"))

    payload.setdefault("list_name", "提醒事项")
    payload.setdefault("priority", "none")
    payload.setdefault("flagged", False)
    result["calendar"] = None
    result.setdefault("reply", None)
    result.setdefault("error", None)


def _validate_none(result: dict[str, Any]) -> None:
    if result.get("error"):
        raise AgentValidationError(f"model did not return a valid tool call: {result['error']}")
    reply = result.get("reply")
    if not isinstance(reply, str) or not reply.strip():
        result["reply"] = "截图中没有识别到日程或任务"
    result["calendar"] = None
    result["reminder"] = None
    result.setdefault("error", None)


def _validate_recurrence(recurrence: Any) -> None:
    if recurrence is None:
        return
    if not isinstance(recurrence, dict):
        raise AgentValidationError("recurrence must be an object")

    frequency = recurrence.get("frequency")
    if frequency not in VALID_RECURRENCE_FREQUENCIES:
        raise AgentValidationError(f"invalid recurrence frequency: {frequency}")

    interval = recurrence.get("interval", 1)
    if not isinstance(interval, int) or interval < 1:
        raise AgentValidationError("recurrence interval must be a positive integer")

    weekdays = recurrence.get("weekdays")
    if weekdays is not None:
        if not isinstance(weekdays, list) or any(day not in VALID_WEEKDAYS for day in weekdays):
            raise AgentValidationError("recurrence weekdays contains invalid values")

    end_date = recurrence.get("end_date")
    if not _is_blank(end_date):
        if not isinstance(end_date, str):
            raise AgentValidationError("recurrence end_date must be a string")
        _parse_date_or_datetime(end_date, "recurrence end_date")

    occurrence_count = recurrence.get("occurrence_count")
    if occurrence_count is not None and (not isinstance(occurrence_count, int) or occurrence_count < 1):
        raise AgentValidationError("recurrence occurrence_count must be a positive integer")


def _validate_optional_nonnegative_int(payload: dict[str, Any], key: str) -> None:
    value = payload.get(key)
    if value is not None and (not isinstance(value, int) or value < 0):
        raise AgentValidationError(f"{key} must be a non-negative integer")


def _parse_date_or_datetime(value: str, label: str) -> tuple[datetime, bool]:
    try:
        parsed_date = date.fromisoformat(value)
        return datetime.combine(parsed_date, time.min), True
    except ValueError:
        pass

    try:
        normalized = value.replace("Z", "+00:00")
        parsed = datetime.fromisoformat(normalized)
        if parsed.tzinfo is not None:
            parsed = parsed.astimezone(timezone.utc).replace(tzinfo=None)
        return parsed, False
    except ValueError as exc:
        raise AgentValidationError(f"{label} must be ISO8601") from exc


def _parse_time(value: str, label: str) -> time:
    for fmt in ("%H:%M", "%H:%M:%S"):
        try:
            return datetime.strptime(value, fmt).time()
        except ValueError:
            continue
    raise AgentValidationError(f"{label} must be HH:MM or HH:MM:SS")


def _is_blank(value: Any) -> bool:
    return value is None or (isinstance(value, str) and not value.strip())
