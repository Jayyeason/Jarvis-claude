def normalize_tool_result(tool_name: str, args: dict) -> dict:
    args = args or {}
    if tool_name == "create_calendar_event":
        return {
            "type": "calendar",
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
            "reply": None,
            "error": None,
        }
    if tool_name == "create_reminder":
        return {
            "type": "reminder",
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
            "reply": None,
            "error": None,
        }
    return {
        "type": "none",
        "calendar": None,
        "reminder": None,
        "reply": args.get("reply", "截图中没有识别到日程或任务"),
        "error": None,
    }
