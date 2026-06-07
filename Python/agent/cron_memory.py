from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from datetime import datetime, timedelta
from uuid import uuid4

from .memory import MemoryManager


CRON_SECTION_HEADING = "## Cron 规则"
CRON_ID_PREFIX = "cron_"
CRON_FIELD_RE = re.compile(
    r"(?:^|\|)\s*[-*]?\s*(id|cron|title|body)\s*:\s*(.*?)(?=\s*\|\s*(?:id|cron|title|body)\s*:|$)",
    flags=re.IGNORECASE,
)


@dataclass(frozen=True)
class CronTask:
    id: str
    cron_expr: str
    title: str
    body: str
    raw_line: str = ""


def cron_help_text() -> str:
    return (
        "⏰ **Cron 命令**\n\n"
        "- `/cron 每天上午10点提醒我做复盘`\n"
        "- `/cron-list` 查看已有 Cron 提醒\n"
        "- `/cron-delete <cron-id>` 删除某个 Cron 提醒\n"
        "- `/cron-help` 查看帮助\n\n"
        "这些提醒会在 Jarvis 岛和系统通知中弹出；解析 `/cron` 自然语言时会调用当前启用的大模型。"
    )


def read_cron_tasks(memory: MemoryManager) -> list[CronTask]:
    memory.ensure_files()
    tasks: list[CronTask] = []
    for line in memory.read_heartbeat_rules().splitlines():
        task = parse_cron_task_line(line)
        if task:
            tasks.append(task)
    return tasks


def append_cron_task(memory: MemoryManager, cron_expr: str, title: str, body: str = "") -> CronTask:
    expr = validate_cron_expr(cron_expr)
    task = CronTask(
        id=_new_cron_id(),
        cron_expr=expr,
        title=_clean_field(title) or "周期提醒",
        body=_clean_field(body) or _clean_field(title) or "周期提醒",
    )
    line = format_cron_task_line(task)
    updated = _append_line_to_cron_section(memory.read_heartbeat_rules(), line)
    memory.update_managed_file("heartbeat", updated)
    return parse_cron_task_line(line) or task


def delete_cron_task(memory: MemoryManager, cron_id: str) -> bool:
    target = _clean_identifier(cron_id)
    if not target:
        return False

    lines = memory.read_heartbeat_rules().splitlines()
    updated_lines: list[str] = []
    removed = False
    for line in lines:
        task = parse_cron_task_line(line)
        if task and task.id == target:
            removed = True
            continue
        updated_lines.append(line)

    if removed:
        memory.update_managed_file("heartbeat", "\n".join(updated_lines).rstrip() + "\n")
    return removed


def validate_cron_expr(cron_expr: str) -> str:
    expr = _clean_field(cron_expr)
    if len(expr.split()) != 5:
        raise ValueError("Cron 表达式必须是 5 字段：分 时 日 月 周")
    try:
        from croniter import croniter

        croniter(expr, datetime.now()).get_next(datetime)
    except Exception as exc:
        try:
            _validate_cron_expr_fallback(expr)
        except ValueError as fallback_exc:
            raise ValueError(f"无效 Cron 表达式：{expr}") from fallback_exc
    return expr


def previous_cron_time(cron_expr: str, now: datetime) -> datetime:
    expr = validate_cron_expr(cron_expr)
    try:
        from croniter import croniter

        return croniter(expr, now).get_prev(datetime)
    except Exception:
        return _previous_cron_time_fallback(expr, now)


def describe_cron_expr(cron_expr: str) -> str:
    expr = validate_cron_expr(cron_expr)
    minute, hour, day, month, weekday = expr.split()
    if minute.isdigit() and hour.isdigit():
        time_text = f"{int(hour):02d}:{int(minute):02d}"
    else:
        time_text = expr

    if day == "*" and month == "*" and weekday == "*":
        return f"每天 {time_text}"
    if day == "*" and month == "*" and weekday in {"1-5", "1,2,3,4,5"}:
        return f"每个工作日 {time_text}"
    if day == "*" and month == "*" and _single_weekday_name(weekday):
        return f"每周{_single_weekday_name(weekday)} {time_text}"
    if month == "*" and weekday == "*" and day.isdigit():
        return f"每月 {int(day)} 日 {time_text}"
    return f"{time_text}（cron: {expr}）"


def parse_cron_task_line(line: str) -> CronTask | None:
    text = (line or "").strip()
    if "cron:" not in text.lower():
        return None

    fields = {match.group(1).lower(): match.group(2).strip(" -|") for match in CRON_FIELD_RE.finditer(text)}
    if fields.get("cron") and any(key in fields for key in ["id", "title", "body"]):
        cron_id = _clean_identifier(fields.get("id") or "") or _legacy_id_for_line(text)
        title = _clean_field(fields.get("title") or "") or "周期提醒"
        body = _clean_field(fields.get("body") or "") or title
        return CronTask(cron_id, _clean_field(fields["cron"]), title, body, raw_line=line)

    try:
        _, rest = text.split("cron:", 1)
    except ValueError:
        return None
    parts = [part.strip(" -|") for part in rest.split("|", 2)]
    if not parts or not parts[0]:
        return None
    title = _clean_field(parts[1]) if len(parts) > 1 else "周期提醒"
    body = _clean_field(parts[2]) if len(parts) > 2 else title
    return CronTask(_legacy_id_for_line(text), _clean_field(parts[0]), title or "周期提醒", body or title, raw_line=line)


def format_cron_task_line(task: CronTask) -> str:
    cron_id = _clean_identifier(task.id) or _new_cron_id()
    expr = _clean_field(task.cron_expr)
    title = _clean_field(task.title) or "周期提醒"
    body = _clean_field(task.body) or title
    return f"- id: {cron_id} | cron: {expr} | title: {title} | body: {body}"


def _append_line_to_cron_section(text: str, line: str) -> str:
    stripped_text = (text or "").rstrip()
    if not stripped_text:
        return f"# heartbeat.md\n\n{CRON_SECTION_HEADING}\n{line}\n"

    lines = stripped_text.splitlines()
    start = next((idx for idx, value in enumerate(lines) if value.strip() == CRON_SECTION_HEADING), None)
    if start is None:
        return stripped_text + f"\n\n{CRON_SECTION_HEADING}\n{line}\n"

    end = len(lines)
    for idx in range(start + 1, len(lines)):
        value = lines[idx].lstrip()
        if value.startswith("## ") and not value.startswith("### "):
            end = idx
            break

    updated = lines[:end] + [line] + lines[end:]
    return "\n".join(updated).rstrip() + "\n"


def _new_cron_id() -> str:
    return CRON_ID_PREFIX + uuid4().hex[:8]


def _legacy_id_for_line(line: str) -> str:
    digest = hashlib.sha1(line.strip().encode("utf-8")).hexdigest()[:8]
    return CRON_ID_PREFIX + digest


def _clean_identifier(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_-]", "", (value or "").strip())
    return cleaned[:64]


def _clean_field(value: str) -> str:
    text = re.sub(r"\s+", " ", (value or "").replace("|", "/")).strip()
    return text[:240]


def _validate_cron_expr_fallback(expr: str) -> None:
    minute, hour, day, month, weekday = expr.split()
    _parse_cron_field(minute, 0, 59)
    _parse_cron_field(hour, 0, 23)
    _parse_cron_field(day, 1, 31)
    _parse_cron_field(month, 1, 12)
    _parse_cron_field(weekday, 0, 7)


def _previous_cron_time_fallback(expr: str, now: datetime) -> datetime:
    minute, hour, day, month, weekday = expr.split()
    minutes = _parse_cron_field(minute, 0, 59)
    hours = _parse_cron_field(hour, 0, 23)
    days = _parse_cron_field(day, 1, 31)
    months = _parse_cron_field(month, 1, 12)
    weekdays = {0 if value == 7 else value for value in _parse_cron_field(weekday, 0, 7)}
    day_any = day == "*"
    weekday_any = weekday == "*"

    cursor = now.replace(second=0, microsecond=0)
    if cursor >= now:
        cursor -= timedelta(minutes=1)

    for _ in range(366 * 24 * 60):
        cron_weekday = (cursor.weekday() + 1) % 7
        if (
            cursor.minute in minutes
            and cursor.hour in hours
            and cursor.month in months
            and _cron_day_matches(cursor.day, cron_weekday, days, weekdays, day_any, weekday_any)
        ):
            return cursor
        cursor -= timedelta(minutes=1)

    raise ValueError(f"找不到上一条 Cron 触发时间：{expr}")


def _cron_day_matches(
    day: int,
    weekday: int,
    days: set[int],
    weekdays: set[int],
    day_any: bool,
    weekday_any: bool,
) -> bool:
    if day_any and weekday_any:
        return True
    if day_any:
        return weekday in weekdays
    if weekday_any:
        return day in days
    return day in days or weekday in weekdays


def _parse_cron_field(field: str, minimum: int, maximum: int) -> set[int]:
    values: set[int] = set()
    for part in field.split(","):
        part = part.strip()
        if not part:
            raise ValueError("empty cron field")
        values.update(_parse_cron_part(part, minimum, maximum))
    if not values:
        raise ValueError("empty cron field")
    return values


def _parse_cron_part(part: str, minimum: int, maximum: int) -> set[int]:
    if "/" in part:
        base, step_text = part.split("/", 1)
        if not step_text.isdigit():
            raise ValueError("invalid cron step")
        step = int(step_text)
        if step <= 0:
            raise ValueError("invalid cron step")
    else:
        base = part
        step = 1

    if base == "*":
        start = minimum
        end = maximum
    elif "-" in base:
        start_text, end_text = base.split("-", 1)
        start = _parse_cron_int(start_text)
        end = _parse_cron_int(end_text)
    else:
        start = _parse_cron_int(base)
        end = maximum if "/" in part else start

    if start < minimum or end > maximum or start > end:
        raise ValueError("cron value out of range")
    return set(range(start, end + 1, step))


def _parse_cron_int(value: str) -> int:
    if not value.isdigit():
        raise ValueError("invalid cron integer")
    return int(value)


def _single_weekday_name(value: str) -> str:
    names = {
        "0": "日",
        "7": "日",
        "1": "一",
        "2": "二",
        "3": "三",
        "4": "四",
        "5": "五",
        "6": "六",
    }
    return names.get(value, "")
