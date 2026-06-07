from __future__ import annotations

import json
import re
from datetime import date, datetime, timedelta
from typing import Any, Optional

from contracts import AssistantActionPlan


SCHEDULE_ACTION_HINTS = [
    "提醒我",
    "记得",
    "待办",
    "日程",
    "安排",
    "加个会",
    "加一个会",
    "开会",
    "会议",
    "吃饭",
    "面试",
    "课程",
    "提交",
    "截止",
    "ddl",
    "报名",
    "缴费",
    "买",
    "电话",
]

TIME_HINTS = [
    "今天",
    "明天",
    "后天",
    "今晚",
    "未来",
    "过去",
    "最近",
    "接下来",
    "下周",
    "周",
    "星期",
    "上午",
    "中午",
    "下午",
    "晚上",
    "点",
    "月",
    "号",
    "前",
]

PREFERENCE_LABELS = {
    "calendar_default_duration_minutes": "日程默认时长",
    "calendar_default_alert_minutes": "日程默认提醒",
    "reminder_default_alert_minutes": "待办默认提前提醒",
    "reminder_default_due_time": "待办默认提醒时间",
}

LOCAL_OPERATION_HINTS = [
    "/list",
    "list",
    "列出",
    "查看",
    "看一下",
    "看下",
    "看看",
    "有什么",
    "有哪些",
    "删除",
    "删掉",
    "取消",
    "移除",
    "推迟",
    "提前",
    "延后",
    "改到",
    "改成",
    "修改",
    "更新",
    "挪到",
    "调整",
]

MEMORY_ACTION_HINTS = [
    "记住",
    "记一下",
    "你要记得",
    "以后",
    "称呼我",
    "叫我",
    "喊我",
    "我的名字",
    "我叫",
    "我住在",
    "我在",
    "我的城市",
    "我偏好",
    "我喜欢",
    "我希望你",
    "以后回答",
]

CREATE_ACTION_HINTS = [
    "添加",
    "加个",
    "加一个",
    "新增",
    "新建",
    "创建",
    "写入",
    "记到",
    "安排",
    "帮我加",
]

CREATE_CONFIRM_HINTS = [
    "确认",
    "确认添加",
    "添加",
    "加上",
    "可以",
    "对",
    "没问题",
    "没错",
    "是的",
    "好",
    "行",
]


def parse_preference_update(message: str) -> Optional[dict[str, Any]]:
    text = _normalize_text(message)
    if not text or "默认" not in text:
        return None

    values: dict[str, Any] = {}

    duration = _extract_duration_minutes(text)
    if duration is not None and _contains_any(text, ["时长", "持续", "多久"]):
        values["calendar_default_duration_minutes"] = duration

    if "提前" in text:
        minutes = _extract_duration_minutes(text)
        if minutes is not None:
            if _contains_any(text, ["待办", "提醒事项", "任务", "reminder"]):
                values["reminder_default_alert_minutes"] = minutes
            elif _contains_any(text, ["日程", "会议", "活动", "calendar"]):
                values["calendar_default_alert_minutes"] = minutes
            else:
                values["calendar_default_alert_minutes"] = minutes
                values["reminder_default_alert_minutes"] = minutes
    elif duration is not None and _contains_any(text, ["提醒时间", "提醒", "alert"]):
        if _contains_any(text, ["待办", "提醒事项", "任务", "reminder"]):
            values["reminder_default_alert_minutes"] = duration
        elif _contains_any(text, ["日程", "会议", "活动", "calendar"]):
            values["calendar_default_alert_minutes"] = duration
        else:
            values["calendar_default_alert_minutes"] = duration
            values["reminder_default_alert_minutes"] = duration

    if _contains_any(text, ["待办", "提醒事项", "任务", "reminder"]) and "提前" not in text:
        due_time = _extract_time_of_day(text)
        if due_time:
            values["reminder_default_due_time"] = due_time

    if not values:
        return None

    return values


def preference_reply(values: dict[str, Any]) -> str:
    parts = []
    for key, value in values.items():
        label = PREFERENCE_LABELS.get(key, key)
        if key.endswith("_alert_minutes"):
            parts.append(f"{label}：提前 {value} 分钟")
        elif key == "calendar_default_duration_minutes":
            parts.append(f"{label}：{value} 分钟")
        else:
            parts.append(f"{label}：{value}")
    return "已更新偏好并写入 Memory：" + "；".join(parts)


def is_schedule_request(message: str) -> bool:
    text = _normalize_text(message).lower()
    if not text or parse_preference_update(text):
        return False
    return _contains_any(text, SCHEDULE_ACTION_HINTS) and _contains_any(text, TIME_HINTS)


def is_schedule_creation_request(message: str) -> bool:
    return _looks_like_new_schedule_creation(_normalize_text(message).lower())


def contextual_schedule_creation_text(message: str, history: list[dict]) -> Optional[str]:
    text = _normalize_text(message)
    if not _looks_like_create_confirmation(text):
        return None

    previous_assistant = _last_history_content(history, "assistant")
    previous_user = _last_history_content(history, "user")
    context = " ".join(item for item in [previous_assistant, previous_user] if item)
    if not context:
        return None
    if not _looks_like_creation_confirmation_context(context):
        return None
    return f"{context}\n用户确认：{text}"


def _looks_like_new_schedule_creation(text: str) -> bool:
    if not is_schedule_request(text):
        return False
    if _contains_any(text, ["列出", "查看", "看看", "有哪些", "有什么", "删除", "删掉", "取消", "移除"]):
        return False
    if _contains_any(text, ["推迟", "延后", "改到", "改成", "修改", "更新", "挪到", "调整"]):
        return False
    explicit_create = _contains_any(text, CREATE_ACTION_HINTS)
    if explicit_create:
        return True
    if _looks_like_existing_alert_target(text):
        return False

    duration_or_alert = _contains_any(text, ["持续", "时长", "大概", "大约", "左右", "提醒我"])
    calendar_event = _contains_any(text, ["开会", "会议", "吃饭", "面试", "课程", "活动", "出差", "看展"])
    reminder_task = _contains_any(text, ["记得", "提交", "交作业", "缴费", "报名", "买"])

    return duration_or_alert and (calendar_event or reminder_task)


def _looks_like_create_confirmation(text: str) -> bool:
    normalized = _normalize_text(text).lower()
    if not normalized or len(normalized) > 24:
        return False
    return _contains_any(normalized, CREATE_CONFIRM_HINTS)


def _looks_like_creation_confirmation_context(text: str) -> bool:
    normalized = _normalize_text(text).lower()
    has_create_context = _contains_any(normalized, ["添加", "新建", "创建", "写入", "加入", "为你添加", "是否确认"])
    has_schedule_context = _contains_any(normalized, ["日程", "待办", "提醒", "答辩", "会议", "开会", "任务"])
    has_time_context = _contains_any(normalized, TIME_HINTS) or _extract_time_of_day(normalized) is not None
    return has_create_context and has_schedule_context and has_time_context


def _looks_like_existing_alert_target(text: str) -> bool:
    if not ("提前" in text and "提醒" in text):
        return False
    date_or_time = r"(?:今天|明天|后天|今晚|明晚|本周|下周|周[一二三四五六日天]|星期[一二三四五六日天]|(?:\d{1,2}\s*月\s*)?\d{1,2}\s*[日号]|(?:凌晨|早上|上午|中午|下午|晚上|夜里)?\s*(?:\d{1,2}|[一二三四五六七八九十两]+)\s*点(?:\s*(?:[0-5]?\d|[一二三四五六七八九十两]+)\s*分?)?)"
    existing_kind = r"(?:日程|待办|提醒事项|任务|会议|开会|活动|课程|面试|吃饭|ddl|截止)"
    return re.search(rf"{date_or_time}\s*的\s*.{{0,18}}{existing_kind}", text, flags=re.IGNORECASE) is not None


def is_contextual_local_operation_request(message: str, history: list[dict]) -> bool:
    text = _normalize_text(message).lower()
    if not text or parse_preference_update(text):
        return False
    if is_local_operation_request(text):
        return True

    previous_user = _last_history_content(history, "user")
    previous_assistant = _last_history_content(history, "assistant")
    if not previous_user or not previous_assistant:
        return False
    if not is_local_operation_request(previous_user):
        return False
    if not _looks_like_local_operation_clarification(previous_assistant):
        return False

    return _looks_like_clarification_answer(text)


def heuristic_contextual_action_plan(
    message: str,
    history: list[dict],
    now: datetime,
) -> Optional[AssistantActionPlan]:
    if not is_contextual_local_operation_request(message, history):
        return None

    previous_user = _last_history_content(history, "user")
    if not previous_user:
        return None

    return heuristic_action_plan(f"{message} {previous_user}", now)


def is_local_operation_request(message: str) -> bool:
    text = _normalize_text(message).lower()
    if not text or parse_preference_update(text):
        return False
    if _looks_like_new_schedule_creation(text):
        return False
    if _is_list_command(text):
        return True
    if _looks_like_implicit_list_request(text):
        return True
    if not _contains_any(text, LOCAL_OPERATION_HINTS):
        return False
    return _contains_any(text, ["日程", "待办", "提醒", "会议", "开会", "安排", "任务", "ddl", "截止"]) or _contains_any(text, TIME_HINTS)


def is_slash_list_request(message: str) -> bool:
    return _is_list_command(_normalize_text(message))


def is_memory_update_request(message: str) -> bool:
    text = _normalize_text(message).lower()
    if not text or parse_preference_update(text):
        return False
    if _looks_like_new_schedule_creation(text) or is_local_operation_request(text):
        return False
    return _contains_any(text, MEMORY_ACTION_HINTS)


def is_cron_help_request(message: str) -> bool:
    return re.match(r"^\s*/cron-help(?:\s|$)", _normalize_text(message), flags=re.IGNORECASE) is not None


def is_cron_list_request(message: str) -> bool:
    return re.match(r"^\s*/cron-list(?:\s|$)", _normalize_text(message), flags=re.IGNORECASE) is not None


def cron_delete_id(message: str) -> Optional[str]:
    match = re.match(r"^\s*/cron-delete\s+([A-Za-z0-9_-]+)\s*$", _normalize_text(message), flags=re.IGNORECASE)
    return match.group(1) if match else None


def is_cron_delete_request(message: str) -> bool:
    return re.match(r"^\s*/cron-delete(?:\s|$)", _normalize_text(message), flags=re.IGNORECASE) is not None


def is_cron_create_request(message: str) -> bool:
    return re.match(r"^\s*/cron(?:\s|$)", _normalize_text(message), flags=re.IGNORECASE) is not None


def cron_command_payload(message: str) -> str:
    return re.sub(r"^\s*/cron\s*", "", _normalize_text(message), count=1, flags=re.IGNORECASE).strip()


def _looks_like_implicit_list_request(text: str) -> bool:
    if _contains_any(text, ["删除", "删掉", "取消", "移除", "推迟", "提前", "延后", "改到", "改成", "修改", "更新", "挪到", "调整"]):
        return False
    has_collection = _contains_any(text, ["日程", "待办", "提醒事项", "提醒", "任务"])
    has_range = _infer_date_range(text, datetime.now().astimezone()) is not None
    return has_collection and has_range


def _is_list_command(text: str) -> bool:
    return re.match(r"^\s*/?list(?:\s|$)", text, flags=re.IGNORECASE) is not None


def _looks_like_local_operation_clarification(text: str) -> bool:
    return _contains_any(text, ["哪一天", "哪一项", "过去", "未来", "包括今天", "具体", "确认"])


def _looks_like_clarification_answer(text: str) -> bool:
    if _looks_like_new_schedule_creation(text):
        return False
    if _infer_date_range(text, datetime.now().astimezone()) is not None:
        return True
    return _contains_any(text, ["未来", "过去", "今天", "明天", "后天"])


def _last_history_content(history: list[dict], role: str) -> Optional[str]:
    for item in reversed(history):
        if item.get("role") == role:
            content = item.get("content")
            if isinstance(content, str) and content.strip():
                return content
    return None


def assistant_system_prompt(memory_context: str) -> str:
    return (
        "你是 Jarvis 的对话助手。用简洁中文回答。\n"
        "你可以闲聊、解释信息、帮助用户组织想法。\n"
        "不要声称自己已经写入日程、待办或偏好；这些操作由系统工具处理。\n"
        "如果用户想创建日程/待办或修改偏好，请简短说明可以继续告诉你具体信息。\n\n"
        f"{memory_context}"
    )


async def plan_assistant_action(
    provider: Any,
    message: str,
    history: list[dict],
    now: datetime,
    memory_context: str = "",
) -> AssistantActionPlan:
    """Ask the active model for a local action plan."""
    system_prompt = assistant_action_planner_prompt(now, memory_context)
    messages = (history + [{"role": "user", "content": message}])[-12:]
    raw = await provider.chat(messages=messages, system_prompt=system_prompt)
    plan = parse_action_plan(raw)
    return normalize_action_plan(plan, message, now)


async def plan_cron_task(
    provider: Any,
    message: str,
    now: datetime,
    memory_context: str = "",
) -> dict[str, str]:
    payload = cron_command_payload(message)
    if not payload:
        raise ValueError("missing cron command payload")

    raw = await provider.chat(
        messages=[{"role": "user", "content": payload}],
        system_prompt=cron_task_planner_prompt(now, memory_context),
    )
    data = _parse_json_object(raw)
    cron_expr = _json_string(data, "cron_expr")
    title = _json_string(data, "title")
    body = _json_string(data, "body") or title
    if not cron_expr or not title:
        raise ValueError("cron planner did not return cron_expr and title")
    return {"cron_expr": cron_expr, "title": title, "body": body}


def assistant_action_planner_prompt(now: datetime, memory_context: str = "") -> str:
    today = now.date().isoformat()
    return (
        "你是 Jarvis 的本地操作规划器，只输出一个 JSON 对象，不要输出 Markdown 或解释。\n"
        f"当前时间：{now.isoformat()}，今天日期：{today}。\n"
        "Jarvis 的 Swift 本地工具会执行你的计划；你不能声称已经执行。\n"
        "可选 action：\n"
        "- chat：闲聊或不需要本地操作。\n"
        "- create_candidates：用户要新建日程或待办。\n"
        "- update_preference：用户明确设置日程/待办偏好。\n"
        "- update_memory：用户明确要求记住长期资料、称呼、城市、交流偏好，或提出 Jarvis 人设/边界修改。\n"
        "- list_items：列出已有日程/待办。\n"
        "- delete_items：删除已有日程/待办，必须 confirmation_required=true。\n"
        "- reschedule_item：推迟、提前、改时间或改地点已有项目，必须 confirmation_required=true。\n"
        "- update_alert：修改已有日程/待办的提醒提前量，不改事件开始时间，通常不需要确认。\n"
        "- clarify：信息不足，无法确定目标、日期、操作或新时间。\n\n"
        "JSON 结构：\n"
        "{\n"
        '  "action": "list_items|delete_items|reschedule_item|update_alert|clarify|chat|create_candidates|update_preference|update_memory",\n'
        '  "reply": "给用户的简短回复",\n'
        '  "clarification_question": "仅 action=clarify 时填写",\n'
        '  "target": {\n'
        '    "item_kind": "calendar|reminder|both",\n'
        '    "title_keywords": ["用于匹配标题的关键词，不要放日期词"],\n'
        '    "date_range": {"start_date": "YYYY-MM-DD", "end_date": "YYYY-MM-DD", "label": "明天"},\n'
        '    "time_of_day": "HH:MM，如果用户指定了目标事项的几点，例如今晚9点的会就填 21:00",\n'
        '    "time_period": "morning|afternoon|evening|night，如果用户只说上午/下午/晚上但没有具体几点",\n'
        '    "raw_text": "用户描述的目标"\n'
        "  },\n"
        '  "patch": {\n'
        '    "shift_minutes": 60,\n'
        '    "alert_minutes_before": 20,\n'
        '    "new_start_time": "YYYY-MM-DDTHH:MM:SS 或 HH:MM",\n'
        '    "new_end_time": "YYYY-MM-DDTHH:MM:SS 或 HH:MM",\n'
        '    "new_due_date": "YYYY-MM-DD",\n'
        '    "new_due_time": "HH:MM",\n'
        '    "title": "新标题",\n'
        '    "location": "新地点"\n'
        "  },\n"
        '  "preference_values": {"calendar_default_alert_minutes": "15"},\n'
        '  "memory_actions": [\n'
        '    {"tool": "set_user_profile", "arguments": {"field": "preferred_name", "value": "khalil"}, "confidence": 0.95, "requires_confirmation": false}\n'
        "  ],\n"
        '  "confirmation_required": true\n'
        "}\n\n"
        "规则：\n"
        "- 只有以 /list 或 list 开头的快速查询会由本地确定性逻辑处理；其它请求都由你判断 action。\n"
        "- “列出明天的日程/待办” => action=list_items，item_kind=both，date_range 为明天 00:00 到后天 00:00。\n"
        "- 所有 list_items 查询都默认 item_kind=both；即使用户只说“日程”或只说“待办/提醒事项”，也同时列出日程和提醒事项。\n"
        "- “最近2天的日程和待办”/“2天内的日程”/“最近两天待办” => action=list_items，item_kind=both；默认从今天开始向后查询，除非用户明确说过去。\n"
        "- 如果上一轮你追问了过去还是未来，用户回答“未来2天”或“过去2天”，要结合上一轮目标继续返回 list_items，不要返回 chat。\n"
        "- “明天下午3点开会，持续1小时，提前30min提醒我” => action=create_candidates；这是新建日程并设置提醒，不是 update_alert。\n"
        "- “删除明天的开会日程” => action=delete_items，item_kind=calendar，关键词可为 [\"开会\"]。\n"
        "- “把明天下午开会日程推迟1小时开始” => action=reschedule_item，patch.shift_minutes=60。\n"
        "- “今天晚上22点的会议提前1小时” => action=reschedule_item，关键词 [\"会议\"]，time_of_day=22:00，patch.shift_minutes=-60；这是修改开始时间，不是提醒。\n"
        "- “周日晚上22点的会议提前1小时” => action=reschedule_item，date_range 为当前或下一次周日，time_of_day=22:00，patch.shift_minutes=-60。\n"
        "- “今晚9点的开会提前20min提醒我” => action=update_alert，item_kind=calendar，关键词 [\"开会\"]，time_of_day=21:00，patch.alert_minutes_before=20；不要把它当成 reschedule_item。\n"
        "- “今天晚上22点的会议提醒提前1小时” => action=update_alert，patch.alert_minutes_before=60；只有明确出现“提醒”才是修改提醒提前量。\n"
        "- “明天的交材料待办提前10分钟提醒” => action=update_alert，item_kind=reminder，关键词 [\"交材料\"]，patch.alert_minutes_before=10。\n"
        "- “提前半小时” => shift_minutes=-30；“推迟/延后1小时” => shift_minutes=60。\n"
        "- 如果删除或改期缺少可匹配日期或目标关键词，使用 clarify，不要猜。\n"
        "- 日程 calendar 是占用一段时间的会议、吃饭、面试、课程、活动、出差、看展。\n"
        "- 待办 reminder 是交作业、缴费、提交材料、报名截止、DDL、买东西、记得做某事。\n"
        "- 只有用户明确要求长期记住时才用 update_memory；普通闲聊、情绪、临时状态不要写 Memory。\n"
        "- “以后称呼我为 khalil” => action=update_memory，tool=set_user_profile，field=preferred_name，value=khalil。\n"
        "- “记住我住在上海”/“我的城市是上海” => tool=set_user_profile，field=city，value=上海。\n"
        "- “我偏好简洁回答”/“以后回答简洁一点” => tool=append_user_memory，category=style，content=偏好简洁回答。\n"
        "- “记住我不吃香菜” => tool=append_user_memory，category=preference，content=不吃香菜。\n"
        "- “记住我的护照号/身份证/密码/密钥...”等敏感隐私 => action=clarify 或 chat，不要写 Memory。\n"
        "- 修改 Jarvis 边界、人设、权限、自动写入原则 => tool=propose_soul_change，requires_confirmation=true，不要直接写 soul.md。\n"
        "- 可用 memory tool 只有 set_user_profile、append_user_memory、update_schedule_preferences、propose_soul_change。\n"
        "- set_user_profile.field 只能是 preferred_name、city、timezone、locale。\n"
        "- append_user_memory.category 只能是 fact、preference、style。\n"
        "- date_range.end_date 使用开区间结束日期，例如明天就是 start_date=明天，end_date=后天。\n"
        "- title_keywords 只放核心名词或动词，不放“明天/下午/日程/待办/提醒”。\n\n"
        f"{memory_context}"
    )


def cron_task_planner_prompt(now: datetime, memory_context: str = "") -> str:
    return (
        "你是 Jarvis 的 Cron 弹窗提醒解析器，只输出一个 JSON 对象，不要输出 Markdown 或解释。\n"
        f"当前本地时间：{now.isoformat()}。\n"
        "把用户的自然语言周期提醒解析成标准 5 字段 cron 表达式：分 时 日 月 周。\n"
        "这些提醒只用于 Jarvis 岛弹窗，不创建 macOS 日程、提醒事项或系统通知。\n\n"
        "JSON 结构：\n"
        '{ "cron_expr": "0 10 * * *", "title": "做复盘", "body": "提醒你做复盘" }\n\n'
        "规则：\n"
        "- “每天上午10点提醒我做复盘” => cron_expr=\"0 10 * * *\"。\n"
        "- “每个工作日下午6点提醒我写日报” => cron_expr=\"0 18 * * 1-5\"。\n"
        "- “每周一上午9点提醒我开周会” => cron_expr=\"0 9 * * 1\"。\n"
        "- “每月1号上午10点提醒我交房租” => cron_expr=\"0 10 1 * *\"。\n"
        "- 上午/下午/晚上要转换成 24 小时制。\n"
        "- title 保留要提醒的核心事项，body 可以是给用户看的完整提醒句。\n"
        "- 如果用户没有说明周期和时间，也要尽力解析；确实无法解析时返回空字符串字段。\n\n"
        f"{memory_context}"
    )


def parse_action_plan(raw: str) -> AssistantActionPlan:
    data = _parse_json_object(raw)
    return AssistantActionPlan(**data)


def _parse_json_object(raw: str) -> dict[str, Any]:
    text = (raw or "").strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", text, flags=re.DOTALL)
        if not match:
            raise
        data = json.loads(match.group(0))
    if not isinstance(data, dict):
        raise ValueError("expected JSON object")
    return data


def _json_string(data: dict[str, Any], key: str) -> str:
    value = data.get(key)
    return value.strip() if isinstance(value, str) else ""


def normalize_action_plan(plan: AssistantActionPlan, message: str, now: datetime) -> AssistantActionPlan:
    parsed_preferences = parse_preference_update(message)
    if parsed_preferences and plan.action in {"chat", "update_preference"}:
        plan.action = "update_preference"
        plan.preference_values = parsed_preferences
        plan.reply = preference_reply(parsed_preferences)
    if plan.action in {"delete_items", "reschedule_item"}:
        plan.confirmation_required = True
    if plan.action == "update_alert":
        plan.confirmation_required = False
    if plan.action == "update_preference":
        if not plan.preference_values:
            plan.preference_values = parsed_preferences
        if not plan.preference_values:
            return AssistantActionPlan(
                action="clarify",
                reply="你想设置哪项偏好？",
                clarification_question="你想设置哪项偏好？",
            )
        plan.confirmation_required = False
    if plan.action == "update_memory":
        if not plan.memory_actions:
            return AssistantActionPlan(
                action="clarify",
                reply="你想让我记住什么？",
                clarification_question="你想让我记住什么？",
            )
        plan.confirmation_required = any(
            action.requires_confirmation or action.tool == "propose_soul_change"
            for action in plan.memory_actions
        )
    if plan.action in {"delete_items", "reschedule_item", "update_alert", "list_items"}:
        if plan.target is None:
            fallback = heuristic_action_plan(message, now)
            if fallback:
                return fallback
            return AssistantActionPlan(
                action="clarify",
                reply="你想操作哪一天、哪一项？",
                clarification_question="你想操作哪一天、哪一项？",
            )
        plan.target.title_keywords = [_clean_keyword(value) for value in plan.target.title_keywords]
        plan.target.title_keywords = [value for value in plan.target.title_keywords if value]
        if plan.action == "list_items":
            plan.target.item_kind = "both"
        if plan.action in {"delete_items", "reschedule_item", "update_alert"} and (
            not plan.target.date_range or not plan.target.title_keywords
        ):
            return AssistantActionPlan(
                action="clarify",
                reply="你想操作哪一天、哪一项？",
                clarification_question="你想操作哪一天、哪一项？",
                target=plan.target,
            )
    if plan.action == "reschedule_item" and plan.patch is None:
        return AssistantActionPlan(
            action="clarify",
            reply="你想把它改到什么时候？",
            clarification_question="你想把它改到什么时候？",
            target=plan.target,
        )
    if plan.action == "update_alert" and (plan.patch is None or plan.patch.alert_minutes_before is None):
        return AssistantActionPlan(
            action="clarify",
            reply="你想提前多久提醒？",
            clarification_question="你想提前多久提醒？",
            target=plan.target,
        )
    if plan.action == "clarify" and not plan.reply:
        plan.reply = plan.clarification_question or "我需要再确认一下。"
    return plan


def heuristic_action_plan(message: str, now: datetime) -> Optional[AssistantActionPlan]:
    text = _normalize_text(message)
    if not text:
        return None
    if _looks_like_new_schedule_creation(text):
        return None
    alert_plan = heuristic_alert_update_plan(text, now)
    if alert_plan:
        return alert_plan

    action: Optional[str] = None
    if _is_list_command(text) or _contains_any(text, ["列出", "查看", "看一下", "看下", "看看", "有哪些", "有什么"]) or _looks_like_implicit_list_request(text):
        action = "list_items"
    elif _contains_any(text, ["删除", "删掉", "取消", "移除"]):
        action = "delete_items"
    elif _contains_any(text, ["推迟", "提前", "延后", "改到", "改成", "修改", "更新", "挪到", "调整"]):
        action = "reschedule_item"
    if not action:
        return None

    target = {
        "item_kind": "both" if action == "list_items" else _infer_item_kind(text),
        "title_keywords": _extract_title_keywords(text),
        "date_range": _infer_date_range(text, now),
        "time_of_day": _extract_time_of_day(text),
        "time_period": _infer_time_period(text),
        "raw_text": text,
    }
    if action in {"delete_items", "reschedule_item"} and (not target["title_keywords"] or not target["date_range"]):
        return AssistantActionPlan(
            action="clarify",
            reply="你想操作哪一天、哪一项？",
            clarification_question="你想操作哪一天、哪一项？",
        )

    patch = None
    if action == "reschedule_item":
        patch = _infer_operation_patch(text)
        if patch is None:
            return AssistantActionPlan(
                action="clarify",
                reply="你想把它改到什么时候？",
                clarification_question="你想把它改到什么时候？",
                target=target,
            )

    reply = {
        "list_items": "我来查一下。",
        "delete_items": "我会先找到匹配项，确认后再删除。",
        "reschedule_item": "我会先找到匹配项，确认后再修改。",
    }[action]
    return AssistantActionPlan(
        action=action,
        reply=reply,
        target=target,
        patch=patch,
        confirmation_required=action != "list_items",
    )


def heuristic_alert_update_plan(message: str, now: datetime) -> Optional[AssistantActionPlan]:
    text = _normalize_text(message)
    if not text or "提醒" not in text or "提前" not in text:
        return None
    if _looks_like_new_schedule_creation(text):
        return None

    minutes = _extract_duration_minutes(text)
    if minutes is None:
        return None

    item_kind = _infer_item_kind(text)
    target = {
        "item_kind": item_kind,
        "title_keywords": _extract_title_keywords(text),
        "date_range": _infer_date_range(text, now),
        "time_of_day": _extract_time_of_day(text),
        "time_period": _infer_time_period(text),
        "raw_text": text,
    }
    if not target["title_keywords"] or not target["date_range"]:
        return AssistantActionPlan(
            action="clarify",
            reply="你想修改哪一天、哪一项的提醒？",
            clarification_question="你想修改哪一天、哪一项的提醒？",
        )

    return AssistantActionPlan(
        action="update_alert",
        reply="我来找到这项并修改提醒时间。",
        target=target,
        patch={"alert_minutes_before": minutes},
        confirmation_required=False,
    )


def _normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", (value or "").strip())


def _contains_any(text: str, values: list[str]) -> bool:
    lowered = text.lower()
    return any(value.lower() in lowered for value in values)


def _parse_day_count(value: str) -> Optional[int]:
    text = (value or "").strip()
    if not text:
        return None
    if text.isdigit():
        return int(text)

    digits = {
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
    if text == "十":
        return 10
    if "十" in text:
        before, after = text.split("十", 1)
        tens = 1 if before == "" else digits.get(before)
        ones = 0 if after == "" else digits.get(after)
        if tens is None or ones is None:
            return None
        return tens * 10 + ones
    return digits.get(text)


def _extract_duration_minutes(text: str) -> Optional[int]:
    number = r"(\d{1,4}|[一二两三四五六七八九十]+)"
    minute = re.search(rf"{number}\s*(?:min|分钟|分)", text, flags=re.IGNORECASE)
    if minute:
        value = _parse_day_count(minute.group(1))
        return value
    hour = re.search(rf"{number}\s*(?:h|小时|个小时)", text, flags=re.IGNORECASE)
    if hour:
        value = _parse_day_count(hour.group(1))
        return value * 60 if value is not None else None
    return None


def _extract_time_of_day(text: str) -> Optional[str]:
    colon = re.search(r"(?<!\d)([01]?\d|2[0-3])[:：]([0-5]\d)(?!\d)", text)
    if colon:
        return f"{int(colon.group(1)):02d}:{int(colon.group(2)):02d}"

    match = re.search(r"(凌晨|早上|上午|中午|下午|晚上|夜里)?\s*(\d{1,2}|[一二两三四五六七八九十]+)\s*点\s*(半|[0-5]?\d\s*分?)?", text)
    if not match:
        return None

    period = match.group(1) or ""
    hour = _parse_day_count(match.group(2))
    if hour is None:
        return None
    minute_text = (match.group(3) or "").strip()
    minute = 30 if minute_text == "半" else 0
    if minute_text and minute_text != "半":
        digits = re.search(r"\d{1,2}", minute_text)
        if digits:
            minute = int(digits.group(0))

    if (period in {"下午", "晚上", "夜里"} or (not period and "今晚" in text)) and hour < 12:
        hour += 12
    elif period == "中午" and hour < 11:
        hour += 12

    if 0 <= hour <= 23 and 0 <= minute <= 59:
        return f"{hour:02d}:{minute:02d}"
    return None


def _infer_time_period(text: str) -> Optional[str]:
    if _contains_any(text, ["凌晨", "夜里", "深夜"]):
        return "night"
    if _contains_any(text, ["晚上", "今晚"]):
        return "evening"
    if _contains_any(text, ["下午"]):
        return "afternoon"
    if _contains_any(text, ["早上", "上午"]):
        return "morning"
    return None


def _extract_calendar_name(text: str) -> Optional[str]:
    patterns = [
        r"默认(?:写入|使用|放到|放进)?\s*[「\"]?(.+?)[」\"]?\s*日历",
        r"默认日历(?:为|是|叫|设为|设置为)?\s*[「\"]?(.+?)[」\"]?$",
    ]
    return _extract_named_value(text, patterns)


def _extract_list_name(text: str) -> Optional[str]:
    patterns = [
        r"默认(?:提醒)?(?:列表|清单)(?:为|是|叫|设为|设置为)?\s*[「\"]?(.+?)[」\"]?$",
        r"(?:待办|提醒事项|任务).*默认(?:写入|使用|放到|放进)?\s*[「\"]?(.+?)[」\"]?\s*(?:列表|清单)",
    ]
    return _extract_named_value(text, patterns)


def _extract_named_value(text: str, patterns: list[str]) -> Optional[str]:
    for pattern in patterns:
        match = re.search(pattern, text, flags=re.IGNORECASE)
        if not match:
            continue
        value = match.group(1).strip(" 。，,.；;：:\"'「」")
        if value and len(value) <= 40:
            return value
    return None


def _infer_item_kind(text: str) -> str:
    reminder_like = _contains_any(text, ["待办", "提醒事项", "任务", "ddl", "截止", "缴费", "交作业", "提交", "买"])
    calendar_like = _contains_any(text, ["日程", "会议", "开会", "活动", "课程", "面试", "吃饭"])
    if reminder_like and calendar_like:
        return "both"
    if reminder_like:
        return "reminder"
    if calendar_like:
        return "calendar"
    return "both"


def _infer_date_range(text: str, now: datetime) -> Optional[dict[str, str]]:
    base = now.date()
    label = None
    start: Optional[date] = None

    day_count_pattern = r"(\d{1,2}|[一二两三四五六七八九十]+)"
    for keyword in ["未来", "接下来", "过去", "最近"]:
        is_past = keyword == "过去"

        def _make_range(n_days: int, kw: str) -> dict[str, str]:
            if is_past:
                s = base - timedelta(days=n_days - 1)
                e = base + timedelta(days=1)
            else:
                s = base
                e = base + timedelta(days=n_days)
            return {"start_date": s.isoformat(), "end_date": e.isoformat(), "label": kw}

        match = re.search(rf"{keyword}\s*{day_count_pattern}\s*天", text)
        if match:
            days = _parse_day_count(match.group(1))
            if days is not None:
                return _make_range(max(1, days), f"{keyword}{days}天")

        match = re.search(rf"{keyword}\s*{day_count_pattern}\s*(?:周|星期|个星期)", text)
        if match:
            weeks = _parse_day_count(match.group(1))
            if weeks is not None:
                return _make_range(max(1, weeks) * 7, f"{keyword}{weeks}周")

        match = re.search(rf"{keyword}\s*{day_count_pattern}\s*个月", text)
        if match:
            months = _parse_day_count(match.group(1))
            if months is not None:
                return _make_range(max(1, months) * 30, f"{keyword}{months}个月")

    match = re.search(rf"(?<!\d){day_count_pattern}\s*天(?:内|以内)", text)
    if match:
        days = _parse_day_count(match.group(1))
        if days is None:
            return None
        days = max(1, days)
        start = base
        end = base + timedelta(days=days)
        label = f"{days}天内"
        return {"start_date": start.isoformat(), "end_date": end.isoformat(), "label": label}

    match = re.search(rf"(?<!\d){day_count_pattern}\s*(?:周|个星期)(?:内|以内)?", text)
    if match:
        weeks = _parse_day_count(match.group(1))
        if weeks is not None:
            days = max(1, weeks) * 7
            start = base
            end = base + timedelta(days=days)
            return {"start_date": start.isoformat(), "end_date": end.isoformat(), "label": f"{weeks}周内"}

    match = re.search(rf"(?<!\d){day_count_pattern}\s*个月(?:内|以内)?", text)
    if match:
        months = _parse_day_count(match.group(1))
        if months is not None:
            days = max(1, months) * 30
            start = base
            end = base + timedelta(days=days)
            return {"start_date": start.isoformat(), "end_date": end.isoformat(), "label": f"{months}个月内"}

    if "后天" in text:
        start = base + timedelta(days=2)
        label = "后天"
    elif "明天" in text:
        start = base + timedelta(days=1)
        label = "明天"
    elif "今天" in text or "今晚" in text:
        start = base
        label = "今天"

    if start is None:
        weekday = _infer_weekday_date(text, base)
        if weekday:
            start, label = weekday

    if start is None:
        match = re.search(r"(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]?", text)
        if match:
            month = int(match.group(1))
            day = int(match.group(2))
            year = base.year
            candidate = date(year, month, day)
            if candidate < base:
                candidate = date(year + 1, month, day)
            start = candidate
            label = f"{month}月{day}日"

    if start is None:
        return None
    end = start + timedelta(days=1)
    return {"start_date": start.isoformat(), "end_date": end.isoformat(), "label": label or start.isoformat()}


def _infer_weekday_date(text: str, base: date) -> Optional[tuple[date, str]]:
    match = re.search(r"(?:(本周|这周|下周|下个周|下星期|下个星期)\s*)?(?:周|星期|礼拜)\s*([一二三四五六日天])", text)
    if not match:
        return None

    prefix = match.group(1) or ""
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
    target_weekday = weekday_map[match.group(2)]
    delta = (target_weekday - base.weekday()) % 7
    if prefix in {"下周", "下个周", "下星期", "下个星期"}:
        delta += 7
    candidate = base + timedelta(days=delta)
    label = f"{'下周' if prefix in {'下周', '下个周', '下星期', '下个星期'} else ''}周{match.group(2)}"
    return candidate, label


def _extract_title_keywords(text: str) -> list[str]:
    cleaned = text
    for value in [
        "/list",
        "list",
        "列出",
        "查看",
        "看一下",
        "看下",
        "看看",
        "有哪些",
        "有什么",
        "删除",
        "删掉",
        "取消",
        "移除",
        "把",
        "将",
        "帮我",
        "给我",
        "我",
        "了",
        "一下",
        "这个",
        "那个",
        "这",
        "那",
        "的",
        "和",
        "日程",
        "待办",
        "提醒事项",
        "提醒",
        "任务",
        "今天",
        "明天",
        "后天",
        "今晚",
        "未来",
        "过去",
        "最近",
        "接下来",
        "上午",
        "中午",
        "下午",
        "晚上",
        "凌晨",
        "早上",
        "夜里",
        "开始",
        "推迟",
        "提前",
        "延后",
        "改到",
        "改成",
        "修改",
        "更新",
        "挪到",
        "调整",
    ]:
        cleaned = cleaned.replace(value, " ")
    cleaned = re.sub(r"(?:\d{1,2}|[一二两三四五六七八九十]+)\s*天(?:内|以内)?", " ", cleaned)
    cleaned = re.sub(r"(?:\d{1,2}|[一二两三四五六七八九十]+)\s*(?:周|个星期|星期)(?:内|以内)?", " ", cleaned)
    cleaned = re.sub(r"(?:\d{1,2}|[一二两三四五六七八九十]+)\s*个月(?:内|以内)?", " ", cleaned)
    cleaned = re.sub(r"(?:本周|这周|下周|下个周|下星期|下个星期)?\s*(?:周|星期|礼拜)\s*[一二三四五六日天]", " ", cleaned)
    cleaned = re.sub(r"\d{1,2}[:：]\d{2}", " ", cleaned)
    cleaned = re.sub(r"(?:\d{1,2}|[一二两三四五六七八九十]+)\s*(?:点|小时|分钟|分|h|min)", " ", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"[，。,.；;：:！？!?\"'“”‘’（）()/／、&]", " ", cleaned)
    parts = [part.strip() for part in cleaned.split() if part.strip()]
    keywords = []
    for part in parts:
        keyword = _clean_keyword(part)
        if keyword and keyword not in keywords:
            keywords.append(keyword)
    return keywords[:4]


def _clean_keyword(value: str) -> str:
    keyword = re.sub(r"^(的|个|一个|这|这个|那|那个)+", "", (value or "").strip())
    keyword = re.sub(r"(的|了|日程|待办|提醒|事项|任务)$", "", keyword)
    return keyword.strip()


def _infer_operation_patch(text: str) -> Optional[dict[str, Any]]:
    shift = _extract_shift_minutes(text)
    if shift is not None:
        return {"shift_minutes": shift}

    time_value = _extract_time_of_day(text)
    if time_value:
        return {"new_start_time": time_value, "new_due_time": time_value}

    return None


def _extract_shift_minutes(text: str) -> Optional[int]:
    sign: Optional[int] = None
    if _contains_any(text, ["推迟", "延后", "延期"]):
        sign = 1
    elif "提前" in text:
        sign = -1
    if sign is None:
        return None

    if "半小时" in text or "半个小时" in text:
        return sign * 30

    number = r"(\d{1,4}|[一二两三四五六七八九十]+)"
    hour = re.search(rf"{number}\s*(?:h|小时|个小时)", text, flags=re.IGNORECASE)
    if hour:
        value = _parse_day_count(hour.group(1))
        return sign * value * 60 if value is not None else None

    minute = re.search(rf"{number}\s*(?:min|分钟|分)", text, flags=re.IGNORECASE)
    if minute:
        value = _parse_day_count(minute.group(1))
        return sign * value if value is not None else None
    return None
