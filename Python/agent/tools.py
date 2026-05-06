from copy import deepcopy


RECURRENCE_SCHEMA = {
    "type": "object",
    "properties": {
        "frequency": {
            "type": "string",
            "description": "重复频率：daily / weekly / monthly / yearly",
            "enum": ["daily", "weekly", "monthly", "yearly"],
        },
        "interval": {"type": "integer", "minimum": 1, "description": "重复间隔，默认 1"},
        "weekdays": {
            "type": "array",
            "description": "每周重复的星期，weekly 时使用",
            "items": {
                "type": "string",
                "enum": [
                    "monday",
                    "tuesday",
                    "wednesday",
                    "thursday",
                    "friday",
                    "saturday",
                    "sunday",
                ],
            },
        },
        "end_date": {"type": "string", "description": "重复结束日期 YYYY-MM-DD"},
        "occurrence_count": {"type": "integer", "minimum": 1, "description": "重复次数"},
    },
}


ANTHROPIC_TOOLS = [
    {
        "name": "create_calendar_event",
        "description": "识别到日程类事件时调用，写入 macOS Calendar",
        "input_schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string", "description": "事件标题"},
                "notes": {"type": "string", "description": "备注，识别不到则省略"},
                "location": {"type": "string", "description": "地点文字，识别不到则省略"},
                "start_time": {"type": "string", "description": "开始时间 ISO8601；全天可用 YYYY-MM-DD"},
                "end_time": {"type": "string", "description": "结束时间 ISO8601；全天可用 YYYY-MM-DD"},
                "is_all_day": {"type": "boolean", "description": "是否全天日程"},
                "needs_duration": {"type": "boolean", "description": "end_time 缺失时设为 true"},
                "recurrence": RECURRENCE_SCHEMA,
                "travel_time_minutes": {"type": "integer", "minimum": 0, "description": "行程时间分钟数，无则省略"},
                "alert_minutes_before_start": {"type": "integer", "minimum": 0, "description": "开始前多少分钟提醒，默认 10"},
                "calendar_name": {"type": "string", "description": "目标日历名称，缺省使用系统默认日历"},
                "url": {"type": "string", "description": "相关链接，如 Zoom / Teams / 课程页面"},
            },
            "required": ["title", "start_time"],
        },
    },
    {
        "name": "create_reminder",
        "description": "识别到提醒/任务类事件时调用，写入 macOS Reminders",
        "input_schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string", "description": "提醒标题"},
                "notes": {"type": "string", "description": "备注，识别不到则省略"},
                "location": {"type": "string", "description": "地点文字，识别不到则省略"},
                "due_date": {"type": "string", "description": "到期日期 YYYY-MM-DD，识别不到则省略"},
                "due_time": {"type": "string", "description": "到期时间 HH:MM，识别不到则省略"},
                "recurrence": RECURRENCE_SCHEMA,
                "alert_minutes_before_due": {"type": "integer", "minimum": 0, "description": "到期前多少分钟提醒"},
                "list_name": {"type": "string", "description": "目标提醒列表名称，默认 提醒事项"},
                "priority": {
                    "type": "string",
                    "description": "优先级，默认 none",
                    "enum": ["none", "low", "medium", "high"],
                },
                "flagged": {"type": "boolean", "description": "是否旗标，默认 false"},
                "url": {"type": "string", "description": "相关链接，如作业提交页面"},
            },
            "required": ["title"],
        },
    },
    {
        "name": "no_event",
        "description": "截图中没有识别到日程或任务时调用",
        "input_schema": {
            "type": "object",
            "properties": {
                "reply": {"type": "string", "description": "向用户说明原因"},
            },
            "required": ["reply"],
        },
    },
]


def get_anthropic_tools() -> list[dict]:
    return deepcopy(ANTHROPIC_TOOLS)


def to_openai_tools(tools: list[dict]) -> list[dict]:
    return [
        {
            "type": "function",
            "function": {
                "name": tool["name"],
                "description": tool["description"],
                "parameters": tool["input_schema"],
            },
        }
        for tool in tools
    ]


def get_openai_tools() -> list[dict]:
    return to_openai_tools(get_anthropic_tools())
