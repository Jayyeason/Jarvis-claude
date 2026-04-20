import json
from datetime import datetime
from typing import Optional
from providers.base import BaseProvider

SYSTEM_PROMPT = """你是 Jarvis，用户的 macOS AI 效率助理。

用户会发给你截图，你需要识别其中的日程或任务信息，然后调用对应的工具写入系统。

## 判断规则
- 有持续时长（开会、吃饭、面试、课程、活动）→ 调用 create_calendar_event
- 只有截止时间的任务（交作业、缴费、提交、截止、ddl）→ 调用 create_reminder
- 无法识别 → 调用 no_event，说明原因

## 时间处理
- 当前时间：{current_time}
- 相对时间（"明天"、"下周一"）请转换为绝对 ISO8601 时间
- end_time 无法推断时省略，设 needs_duration: true

只调用一次工具，不要输出额外文字。"""

TOOLS = [
    {
        "name": "create_calendar_event",
        "description": "识别到日程类事件时调用，写入 macOS Calendar",
        "input_schema": {
            "type": "object",
            "properties": {
                "title":          {"type": "string",  "description": "事件标题"},
                "start_time":     {"type": "string",  "description": "开始时间 ISO8601，如 2026-04-20T14:00:00"},
                "end_time":       {"type": "string",  "description": "结束时间 ISO8601，无法推断时省略"},
                "needs_duration": {"type": "boolean", "description": "end_time 缺失时设为 true"},
                "location":       {"type": "string",  "description": "地点文字，识别不到则省略"},
                "notes":          {"type": "string",  "description": "备注，识别不到则省略"},
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
                "title":    {"type": "string", "description": "提醒标题"},
                "due_date": {"type": "string", "description": "到期日期 YYYY-MM-DD，识别不到则省略"},
                "due_time": {"type": "string", "description": "到期时间 HH:MM，识别不到则省略"},
                "priority": {"type": "string", "description": "优先级：none / low / medium / high"},
                "notes":    {"type": "string", "description": "备注，识别不到则省略"},
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

# OpenAI-style tool schema (for non-Anthropic providers)
TOOLS_OPENAI = [
    {
        "type": "function",
        "function": {
            "name": t["name"],
            "description": t["description"],
            "parameters": t["input_schema"],
        },
    }
    for t in TOOLS
]


class JarvisAgent:
    def __init__(self):
        pass

    async def run(
        self,
        message: str,
        image_base64: Optional[str] = None,
        session_id: Optional[str] = None,
        provider: Optional[BaseProvider] = None,
    ) -> dict:
        if provider is None:
            return {"event_type": None, "reply": "请先配置云端 API", "error": "no_provider"}

        current_time = datetime.now().strftime("%Y-%m-%d %H:%M (%A)")
        system = SYSTEM_PROMPT.format(current_time=current_time)

        user_text = message or "请识别这张截图中的日程或任务信息"

        try:
            result = await provider.chat_with_tools(
                messages=[{"role": "user", "content": user_text}],
                image_base64=image_base64,
                system_prompt=system,
                tools=TOOLS,
                tools_openai=TOOLS_OPENAI,
            )
            return result
        except Exception as e:
            return {"event_type": None, "reply": "识别失败，请重试", "error": str(e)}
