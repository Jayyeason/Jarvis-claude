import json
import re
from datetime import datetime
from typing import Optional
from providers.base import BaseProvider

SYSTEM_PROMPT = """你是 Jarvis，用户的 macOS AI 效率助理。

用户会发给你截图，你需要识别其中的日程或任务信息。

## 判断规则
- 有持续时长（开会、吃饭、面试、课程）→ 日程（event_type: "calendar"）
- 有截止时间的任务（交作业、缴费、提交）→ 提醒事项（event_type: "reminder"）
- 无法识别 → event_type: null

## 输出格式（只输出 JSON，不要其他文字）

日程：
{
  "event_type": "calendar",
  "title": "事件标题",
  "start_time": "2026-04-18T14:00:00",
  "end_time": "2026-04-18T15:00:00",
  "needs_duration": false,
  "location": "地点（识别不到则省略）",
  "notes": "备注（识别不到则省略）"
}

说明：end_time 无法推断时省略并设 needs_duration: true

提醒事项：
{
  "event_type": "reminder",
  "title": "任务标题",
  "due_date": "2026-04-20",
  "due_time": "22:00",
  "notes": "备注（识别不到则省略）"
}

无法识别：
{
  "event_type": null,
  "reply": "这张截图中没有识别到日程或任务信息"
}

当前时间：{current_time}
"""


def _extract_json(text: str) -> dict:
    text = text.strip()
    # Try direct parse
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    # Extract from markdown code block
    match = re.search(r"```(?:json)?\s*([\s\S]+?)\s*```", text)
    if match:
        try:
            return json.loads(match.group(1))
        except json.JSONDecodeError:
            pass
    # Find first { ... }
    match = re.search(r"\{[\s\S]+\}", text)
    if match:
        try:
            return json.loads(match.group(0))
        except json.JSONDecodeError:
            pass
    raise ValueError(f"Cannot extract JSON from: {text[:200]}")


class JarvisAgent:
    def __init__(self):
        self.max_retries = 2

    async def run(
        self,
        message: str,
        image_base64: Optional[str] = None,
        session_id: Optional[str] = None,
        provider: Optional[BaseProvider] = None,
    ) -> dict:
        if provider is None:
            return {
                "event_type": None,
                "reply": "请先配置云端 API",
                "error": "no_provider",
            }

        current_time = datetime.now().strftime("%Y-%m-%d %H:%M")
        system = SYSTEM_PROMPT.format(current_time=current_time)

        messages = []
        if message:
            messages.append({"role": "user", "content": message})
        elif image_base64:
            messages.append({"role": "user", "content": "请识别这张截图中的日程或任务信息"})

        last_error = None
        for attempt in range(self.max_retries + 1):
            try:
                raw = await provider.chat(
                    messages=messages,
                    image_base64=image_base64,
                    system_prompt=system,
                )
                result = _extract_json(raw)
                return result
            except Exception as e:
                last_error = e
                if attempt < self.max_retries:
                    messages.append({
                        "role": "assistant",
                        "content": raw if "raw" in dir() else str(e),
                    })
                    messages.append({
                        "role": "user",
                        "content": "请只输出 JSON，不要其他文字。",
                    })

        return {
            "event_type": None,
            "reply": "识别失败，请重试",
            "error": str(last_error),
        }
