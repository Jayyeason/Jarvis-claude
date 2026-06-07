from __future__ import annotations

import json
import logging
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

import httpx

from contracts import HeartbeatTickRequest, HeartbeatTickResponse, ProactiveEvent

from .memory import MemoryManager


logger = logging.getLogger("agent.heartbeat")


class HeartbeatEngine:
    def __init__(self, memory: Optional[MemoryManager] = None):
        self.memory = memory or MemoryManager()
        self.wal_path = self.memory.directory / "wal.jsonl"

    async def tick(self, req: HeartbeatTickRequest) -> HeartbeatTickResponse:
        now = _parse_datetime(req.now) or datetime.now()
        events: list[ProactiveEvent] = []

        events.extend(self._upcoming_event_reminders(req, now))
        events.extend(await self._weather_alert(req, now))
        events.extend(self._todo_followup(req, now))
        events.extend(self._tomorrow_preparation(req, now))
        events.extend(self._cron_rules(now))
        events.extend(self._weekly_consolidation(now))

        return HeartbeatTickResponse(events=events)

    def _upcoming_event_reminders(self, req: HeartbeatTickRequest, now: datetime) -> list[ProactiveEvent]:
        out = []
        for event in req.today_events:
            start = _parse_datetime(event.start_time)
            if not start or event.is_all_day:
                continue
            minutes = (start - now).total_seconds() / 60
            if 0 < minutes <= 30:
                action_id = f"event:{event.id}:{start.date().isoformat()}"
                if self._seen(action_id):
                    continue
                body = f"{event.title} 将在 {start.strftime('%H:%M')} 开始"
                if event.location:
                    body += f"，地点：{event.location}"
                out.append(self._event(action_id, "event_reminder", "即将开始", body))
        return out

    async def _weather_alert(self, req: HeartbeatTickRequest, now: datetime) -> list[ProactiveEvent]:
        if not (now.hour == 7 and now.minute == 30):
            return []
        if not any(e.location for e in req.today_events):
            return []
        action_id = f"weather:{now.date().isoformat()}"
        if self._seen(action_id):
            return []
        try:
            weather = await self._get_weather()
        except Exception as exc:
            logger.info("weather heartbeat skipped: %s", exc)
            self.memory.append_error("weather_alert_failed", {"error": str(exc)})
            return []
        rain = weather.get("rain_probability") or weather.get("precipMM") or "0"
        body = f"今天有外出日程。天气：{weather.get('weather', '未知')}，降水：{rain}。出门前确认雨具和路线。"
        return [self._event(action_id, "weather_alert", "今日外出提醒", body)]

    def _todo_followup(self, req: HeartbeatTickRequest, now: datetime) -> list[ProactiveEvent]:
        if not (now.hour == 18 and now.minute == 0):
            return []
        due = [
            r for r in req.incomplete_reminders
            if r.due_time and (_parse_datetime(r.due_time) or now).date() <= now.date()
        ]
        if not due:
            return []
        action_id = f"todos:{now.date().isoformat()}"
        if self._seen(action_id):
            return []
        names = "、".join(r.title for r in due[:3])
        extra = "" if len(due) <= 3 else f" 等 {len(due)} 项"
        return [self._event(action_id, "todo_followup", "待办跟进", f"今天还有 {names}{extra} 未完成。")]

    def _tomorrow_preparation(self, req: HeartbeatTickRequest, now: datetime) -> list[ProactiveEvent]:
        if not (now.hour == 21 and now.minute == 0):
            return []
        important = [e for e in req.tomorrow_events if not e.is_all_day]
        if not important:
            return []
        action_id = f"prep:{now.date().isoformat()}"
        if self._seen(action_id):
            return []
        names = "、".join(e.title for e in important[:3])
        extra = "" if len(important) <= 3 else f" 等 {len(important)} 个日程"
        return [self._event(action_id, "preparation_reminder", "明日准备", f"明天有 {names}{extra}，建议今晚确认材料和出行安排。")]

    def _cron_rules(self, now: datetime) -> list[ProactiveEvent]:
        try:
            from croniter import croniter
        except Exception:
            return []

        out = []
        for idx, line in enumerate(self.memory.read_heartbeat_rules().splitlines()):
            if "cron:" not in line:
                continue
            try:
                _, rest = line.split("cron:", 1)
                expr, title, body = [part.strip(" -|") for part in rest.split("|", 2)]
                previous = croniter(expr, now).get_prev(datetime)
                if 0 <= (now - previous).total_seconds() <= 65:
                    action_id = f"cron:{idx}:{previous.isoformat(timespec='minutes')}"
                    if not self._seen(action_id):
                        out.append(self._event(action_id, "recurring_rule", title or "周期提醒", body or title))
            except Exception as exc:
                self.memory.append_error("cron_rule_failed", {"line": line, "error": str(exc)})
        return out

    def _weekly_consolidation(self, now: datetime) -> list[ProactiveEvent]:
        if not (now.weekday() == 6 and now.hour == 22 and now.minute == 0):
            return []
        action_id = f"weekly:{now.date().isoformat()}"
        if self._seen(action_id):
            return []
        learning = self.memory.recent_entries("learnings.md", 20)
        errors = self.memory.recent_entries("errors.md", 20)
        if not learning and not errors:
            return []
        self.memory.append_learning("weekly_consolidation_needed", {"learnings": bool(learning), "errors": bool(errors)})
        return [self._event(action_id, "weekly_consolidation", "Jarvis 记忆整理", "本周交互记录已整理，可稍后在 memory 文件中查看。")]

    async def _get_weather(self) -> dict:
        async with httpx.AsyncClient() as client:
            resp = await client.get("https://wttr.in/auto?format=j1", timeout=8)
            resp.raise_for_status()
            data = resp.json()
        current = data["current_condition"][0]
        return {
            "temperature": current.get("temp_C"),
            "feels_like": current.get("FeelsLikeC"),
            "weather": current.get("weatherDesc", [{"value": ""}])[0].get("value"),
            "rain_probability": current.get("precipMM", "0"),
            "humidity": current.get("humidity"),
        }

    def _event(self, action_id: str, trigger_type: str, title: str, body: str) -> ProactiveEvent:
        self._mark(action_id, trigger_type, title, body)
        return ProactiveEvent(id=action_id, trigger_type=trigger_type, title=title, body=body)

    def _seen(self, action_id: str) -> bool:
        if not self.wal_path.exists():
            return False
        try:
            for line in self.wal_path.read_text(encoding="utf-8").splitlines():
                if not line.strip():
                    continue
                if json.loads(line).get("id") == action_id:
                    return True
        except Exception:
            return False
        return False

    def _mark(self, action_id: str, trigger_type: str, title: str, body: str) -> None:
        self.memory.ensure_files()
        entry = {
            "id": action_id,
            "trigger_type": trigger_type,
            "title": title,
            "body": body,
            "status": "pushed",
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        with self.wal_path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(entry, ensure_ascii=False) + "\n")


def _parse_datetime(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).replace(tzinfo=None)
    except ValueError:
        return None
