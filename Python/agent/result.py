def normalize_tool_result(tool_name: str, args: dict) -> dict:
    args = args or {}
    if tool_name == "extract_schedule_items":
        candidates = []
        for idx, item in enumerate(args.get("candidates") or [], start=1):
            if not isinstance(item, dict):
                continue
            candidates.append(_normalize_candidate(item, idx))
        if not candidates:
            return {
                "type": "none",
                "session_id": None,
                "candidates": [],
                "reply": args.get("reply") or "截图中没有识别到日程或任务",
                "error": None,
                "missing_fields": [],
                "prefilled": None,
            }
        return {
            "type": "batch",
            "session_id": None,
            "candidates": candidates,
            "reply": args.get("reply"),
            "error": None,
            "missing_fields": [],
            "prefilled": None,
        }

    if tool_name == "create_calendar_event":
        return {
            "type": "batch",
            "session_id": None,
            "candidates": [_calendar_candidate(args, 1)],
            "reply": None,
            "error": None,
            "missing_fields": [],
            "prefilled": None,
        }
    if tool_name == "create_reminder":
        return {
            "type": "batch",
            "session_id": None,
            "candidates": [_reminder_candidate(args, 1)],
            "reply": None,
            "error": None,
            "missing_fields": [],
            "prefilled": None,
        }
    return {
        "type": "none",
        "session_id": None,
        "candidates": [],
        "reply": args.get("reply", "截图中没有识别到日程或任务"),
        "error": None,
        "missing_fields": [],
        "prefilled": None,
    }


def _normalize_candidate(item: dict, idx: int) -> dict:
    kind = item.get("kind")
    if kind == "calendar":
        return _calendar_candidate(item.get("calendar") or {}, idx, item)
    if kind == "reminder":
        return _reminder_candidate(item.get("reminder") or {}, idx, item)
    if item.get("calendar"):
        return _calendar_candidate(item.get("calendar") or {}, idx, item)
    return _reminder_candidate(item.get("reminder") or item, idx, item)


def _calendar_candidate(args: dict, idx: int, meta: dict | None = None) -> dict:
    meta = meta or {}
    return {
        "id": meta.get("id") or f"candidate_{idx}",
        "kind": "calendar",
        "calendar": {
            "title": args.get("title"),
            "notes": args.get("notes"),
            "location": args.get("location"),
            "start_time": args.get("start_time"),
            "end_time": args.get("end_time"),
            "is_all_day": args.get("is_all_day", False),
            "needs_duration": args.get("needs_duration", False),
            "recurrence": args.get("recurrence"),
            "travel_time_minutes": args.get("travel_time_minutes"),
            "alert_minutes_before_start": args.get("alert_minutes_before_start", 10),
            "calendar_name": args.get("calendar_name"),
            "url": args.get("url"),
        },
        "reminder": None,
        "confidence": meta.get("confidence", 0.8),
        "evidence": meta.get("evidence"),
        "missing_fields": meta.get("missing_fields") or [],
        "clarification_question": meta.get("clarification_question"),
        "conflicts": [],
        "status": "ready",
        "applied_preferences": [],
    }


def _reminder_candidate(args: dict, idx: int, meta: dict | None = None) -> dict:
    meta = meta or {}
    return {
        "id": meta.get("id") or f"candidate_{idx}",
        "kind": "reminder",
        "calendar": None,
        "reminder": {
            "title": args.get("title"),
            "notes": args.get("notes"),
            "location": args.get("location"),
            "due_date": args.get("due_date"),
            "due_time": args.get("due_time"),
            "recurrence": args.get("recurrence"),
            "alert_minutes_before_due": args.get("alert_minutes_before_due"),
            "list_name": args.get("list_name") or "提醒事项",
            "priority": args.get("priority", "none"),
            "flagged": args.get("flagged", False),
            "url": args.get("url"),
        },
        "confidence": meta.get("confidence", 0.8),
        "evidence": meta.get("evidence"),
        "missing_fields": meta.get("missing_fields") or [],
        "clarification_question": meta.get("clarification_question"),
        "conflicts": [],
        "status": "ready",
        "applied_preferences": [],
    }
