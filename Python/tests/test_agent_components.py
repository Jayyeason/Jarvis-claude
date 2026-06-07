import asyncio
import json
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from agent import JarvisAgent
from agent.assistant_chat import (
    cron_command_payload,
    cron_delete_id,
    contextual_schedule_creation_text,
    heuristic_contextual_action_plan,
    heuristic_action_plan,
    is_cron_create_request,
    is_cron_delete_request,
    is_cron_help_request,
    is_cron_list_request,
    is_contextual_local_operation_request,
    is_memory_update_request,
    is_local_operation_request,
    is_schedule_creation_request,
    is_schedule_request,
    is_slash_list_request,
    plan_assistant_action,
    plan_cron_task,
    parse_profile_update,
    parse_preference_update,
    preference_reply,
)
from agent.cron_memory import (
    append_cron_task,
    delete_cron_task,
    describe_cron_expr,
    parse_cron_task_line,
    previous_cron_time,
    read_cron_tasks,
    validate_cron_expr,
)
from agent.heartbeat import HeartbeatEngine
from agent.memory import MEMORY_FILE_WRITE_LIMIT_BYTES, MemoryManager, UserPreferences
from agent.preferences import PreferenceEngine
from agent.prompts import build_system_prompt, normalize_input_mode
from agent.result import normalize_tool_result
from agent.tools import get_anthropic_tools, get_openai_tools
from agent.validator import AgentValidationError, validate_agent_result
from providers.openai_compat import OpenAICompatProvider
from providers.local_model_registry import LocalModelRegistry, safe_model_id
from providers.provider_factory import create_provider
from contracts import AssistantActionPlan, AssistantChatRequest
from gateway import (
    _active_api_key,
    _assistant_extraction_session_id,
    _cron_tasks_reply,
    _execute_memory_actions,
    _mask_secret,
    _normalize_api_keys,
    _set_active_api_key,
    _upsert_api_key,
    app,
    assistant_chat,
)


class _FakeCroniter:
    def __init__(self, expr, base):
        if len(str(expr).split()) != 5:
            raise ValueError("invalid cron")
        self.expr = str(expr)
        self.base = base

    def get_next(self, cls):
        return self.base

    def get_prev(self, cls):
        minute, hour, *_ = self.expr.split()
        if minute.isdigit() and hour.isdigit():
            return self.base.replace(hour=int(hour), minute=int(minute), second=0, microsecond=0)
        return self.base.replace(second=0, microsecond=0)


class MemoryManagerTests(unittest.TestCase):
    def test_missing_file_returns_defaults(self):
        path = Path(tempfile.gettempdir()) / "jarvis-missing-preferences.json"
        if path.exists():
            path.unlink()

        self.assertEqual(MemoryManager(path).load_preferences(), UserPreferences())

    def test_damaged_json_returns_defaults(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "memory.json"
            path.write_text("{bad json", encoding="utf-8")

            self.assertEqual(MemoryManager(path).load_preferences(), UserPreferences())

    def test_loads_known_preference_fields(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "memory.json"
            path.write_text(
                json.dumps(
                    {
                        "preferences": {
                            "calendar_default_duration_minutes": 45,
                            "calendar_default_alert_minutes": 15,
                            "reminder_default_alert_minutes": 5,
                            "reminder_default_due_time": "18:30",
                            "reminder_default_priority_for_deadline": "high",
                        }
                    }
                ),
                encoding="utf-8",
            )

            prefs = MemoryManager(path).load_preferences()

        self.assertEqual(prefs.calendar_default_duration_minutes, 45)
        self.assertEqual(prefs.calendar_default_alert_minutes, 15)
        self.assertEqual(prefs.reminder_default_alert_minutes, 5)
        self.assertEqual(prefs.reminder_default_due_time, "18:30")
        self.assertEqual(prefs.reminder_default_priority_for_deadline, "high")

    def test_loads_legacy_flat_preference_shape_for_custom_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "legacy_preferences.json"
            path.write_text(
                json.dumps({"calendar_default_alert_minutes": 20}),
                encoding="utf-8",
            )

            prefs = MemoryManager(path).load_preferences()

        self.assertEqual(prefs.calendar_default_alert_minutes, 20)

    def test_preference_engine_applies_reminder_due_time(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "memory.json"
            path.write_text(
                json.dumps({"preferences": {"reminder_default_due_time": "20:00"}}),
                encoding="utf-8",
            )
            result = validate_agent_result(
                {
                    "type": "batch",
                    "candidates": [
                        {
                            "id": "candidate_1",
                            "kind": "reminder",
                            "reminder": {"title": "交电费", "due_date": "2026-06-08"},
                        }
                    ],
                }
            )

            applied = PreferenceEngine(MemoryManager(path)).apply(result, "明天记得交电费")
            applied = validate_agent_result(applied)

        candidate = applied["candidates"][0]
        self.assertEqual(candidate["status"], "ready")
        self.assertEqual(candidate["reminder"]["due_time"], "20:00")
        self.assertEqual(candidate["missing_fields"], [])
        self.assertEqual(candidate["applied_preferences"][0]["field"], "reminder.due_time")

    def test_date_only_reminder_without_preference_needs_input(self):
        result = validate_agent_result(
            {
                "type": "batch",
                "candidates": [
                    {
                        "id": "candidate_1",
                        "kind": "reminder",
                        "reminder": {"title": "交电费", "due_date": "2026-06-08"},
                    }
                ],
            }
        )

        candidate = result["candidates"][0]
        self.assertEqual(candidate["status"], "needs_input")
        self.assertIn("time", candidate["missing_fields"])

    def test_preference_engine_applies_calendar_duration_and_alert(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "memory.json"
            path.write_text(
                json.dumps(
                    {
                        "preferences": {
                            "calendar_default_duration_minutes": 45,
                            "calendar_default_alert_minutes": 15,
                        }
                    }
                ),
                encoding="utf-8",
            )
            result = validate_agent_result(
                {
                    "type": "batch",
                    "candidates": [
                        {
                            "id": "candidate_1",
                            "kind": "calendar",
                            "calendar": {
                                "title": "组会",
                                "start_time": "2026-06-08T15:00:00",
                            },
                        }
                    ],
                }
            )

            applied = PreferenceEngine(MemoryManager(path)).apply(result, "明天下午三点组会")
            applied = validate_agent_result(applied)

        candidate = applied["candidates"][0]
        self.assertEqual(candidate["status"], "ready")
        self.assertEqual(candidate["calendar"]["end_time"], "2026-06-08T15:45:00")
        self.assertEqual(candidate["calendar"]["alert_minutes_before_start"], 15)
        self.assertEqual(
            {item["field"] for item in candidate["applied_preferences"]},
            {"calendar.end_time", "calendar.alert_minutes_before_start"},
        )

    def test_preference_engine_applies_system_calendar_defaults_without_memory(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = validate_agent_result(
                {
                    "type": "batch",
                    "candidates": [
                        {
                            "id": "candidate_1",
                            "kind": "calendar",
                            "calendar": {
                                "title": "答辩",
                                "start_time": "2026-06-08T16:00:00",
                            },
                        }
                    ],
                }
            )

            applied = PreferenceEngine(MemoryManager(Path(tmp) / "memory.json")).apply(result, "明天下午4点答辩")
            applied = validate_agent_result(applied)

        candidate = applied["candidates"][0]
        self.assertEqual(candidate["status"], "ready")
        self.assertEqual(candidate["calendar"]["end_time"], "2026-06-08T17:00:00")
        self.assertEqual(candidate["calendar"]["alert_minutes_before_start"], 10)
        self.assertEqual(
            {item["field"]: item["source"] for item in candidate["applied_preferences"]},
            {
                "calendar.end_time": "default",
                "calendar.alert_minutes_before_start": "default",
            },
        )

    def test_preference_engine_keeps_user_provided_duration_and_alert(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = validate_agent_result(
                {
                    "type": "batch",
                    "candidates": [
                        {
                            "id": "candidate_1",
                            "kind": "calendar",
                            "calendar": {
                                "title": "答辩",
                                "start_time": "2026-06-08T16:00:00",
                                "end_time": "2026-06-08T18:00:00",
                                "alert_minutes_before_start": 20,
                            },
                        }
                    ],
                }
            )

            applied = PreferenceEngine(MemoryManager(Path(tmp) / "memory.json")).apply(
                result,
                "明天下午4点到6点答辩，提前20分钟提醒",
            )
            applied = validate_agent_result(applied)

        candidate = applied["candidates"][0]
        self.assertEqual(candidate["calendar"]["end_time"], "2026-06-08T18:00:00")
        self.assertEqual(candidate["calendar"]["alert_minutes_before_start"], 20)
        self.assertEqual(candidate["applied_preferences"], [])

    def test_memory_promotes_stable_written_preference(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "memory.json"
            manager = MemoryManager(path)
            candidate = {
                "id": "candidate_1",
                "kind": "calendar",
                "calendar": {
                    "title": "组会",
                    "start_time": "2026-06-08T15:00:00",
                    "end_time": "2026-06-08T16:00:00",
                    "alert_minutes_before_start": 15,
                },
            }

            manager.learn_from_candidate("written", candidate, "s1")
            manager.learn_from_candidate("written", candidate, "s2")
            manager.learn_from_candidate("written", candidate, "s2")
            status = manager.preferences_status()
            user_markdown = (Path(tmp) / "user.md").read_text(encoding="utf-8")

        self.assertEqual(status["preferences"]["calendar_default_alert_minutes"], 15)
        self.assertEqual(status["preference_meta"]["calendar_default_alert_minutes"]["source"], "learned")
        self.assertIn("- 日程默认提醒：提前 15 分钟", user_markdown)

    def test_update_preferences_syncs_user_markdown_section(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "memory.json"
            manager = MemoryManager(path)
            user_path = Path(tmp) / "user.md"
            user_path.write_text(
                "# user.md\n\n"
                "## 日历与提醒偏好\n"
                "- old value\n\n"
                "## 城市\n"
                "- 上海\n\n"
                "## 自定义\n"
                "- 保留这行\n",
                encoding="utf-8",
            )

            manager.update_preferences({"calendar_default_alert_minutes": 15}, source="manual")
            text = user_path.read_text(encoding="utf-8")

        self.assertIn("- 日程默认提醒：提前 15 分钟", text)
        self.assertNotIn("- old value", text)
        self.assertIn("## 日程与提醒事项偏好", text)
        self.assertNotIn("## 日历与提醒偏好", text)
        self.assertNotIn("## 城市", text)
        self.assertIn("## 用户资料", text)
        self.assertIn("- 城市：上海", text)
        self.assertIn("## 自定义\n- 保留这行", text)

    def test_update_preferences_appends_user_markdown_section_when_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "memory.json"
            manager = MemoryManager(path)
            user_path = Path(tmp) / "user.md"
            user_path.write_text("# user.md\n\n## 城市\n- 北京\n", encoding="utf-8")

            manager.update_preferences({"reminder_default_due_time": "20:00"}, source="manual")
            text = user_path.read_text(encoding="utf-8")
            prompt_context = manager.render_prompt_context()

        self.assertNotIn("## 城市", text)
        self.assertIn("- 城市：北京", text)
        self.assertIn("## 日程与提醒事项偏好", text)
        self.assertIn("- 提醒默认到期时间：20:00", text)
        self.assertIn("20:00", prompt_context)

    def test_managed_files_return_memory_editor_whitelist(self):
        with tempfile.TemporaryDirectory() as tmp:
            manager = MemoryManager(Path(tmp) / "memory.json")

            files = manager.managed_files()

        self.assertEqual([item["id"] for item in files], ["soul", "user", "heartbeat"])
        self.assertEqual([item["filename"] for item in files], ["soul.md", "user.md", "heartbeat.md"])
        self.assertTrue(files[0]["editable"])
        self.assertTrue(files[-1]["editable"])

    def test_update_managed_user_file_updates_prompt_context(self):
        with tempfile.TemporaryDirectory() as tmp:
            manager = MemoryManager(Path(tmp) / "memory.json")
            content = "# user.md\n\n## 偏好\n- 我偏好下午开会\n"

            updated = manager.update_managed_file("user", content)
            prompt_context = manager.render_prompt_context()

        self.assertEqual(updated["content"], content)
        self.assertIn("我偏好下午开会", prompt_context)

    def test_set_user_profile_updates_user_markdown_and_prompt_context(self):
        with tempfile.TemporaryDirectory() as tmp:
            manager = MemoryManager(Path(tmp) / "memory.json")

            update = manager.set_user_profile("preferred_name", "khalil")
            manager.set_user_profile("preferred_name", "Khalil")
            text = (Path(tmp) / "user.md").read_text(encoding="utf-8")
            prompt_context = manager.render_prompt_context()

        self.assertEqual(update["field"], "preferred_name")
        self.assertIn("## 用户资料", text)
        self.assertIn("- 称呼偏好：Khalil", text)
        self.assertNotIn("- 称呼偏好：khalil\n- 称呼偏好：Khalil", text)
        self.assertIn("Khalil", prompt_context)

    def test_set_user_profile_removes_legacy_city_section(self):
        with tempfile.TemporaryDirectory() as tmp:
            manager = MemoryManager(Path(tmp) / "memory.json")
            user_path = Path(tmp) / "user.md"
            user_path.write_text(
                "# user.md\n\n"
                "## 城市\n"
                "- auto\n\n"
                "## 用户资料\n"
                "- 城市：auto\n",
                encoding="utf-8",
            )

            manager.set_user_profile("city", "上海")
            text = user_path.read_text(encoding="utf-8")

        self.assertNotIn("## 城市", text)
        self.assertIn("## 用户资料\n- 城市：上海", text)

    def test_append_user_memory_deduplicates_long_term_preference(self):
        with tempfile.TemporaryDirectory() as tmp:
            manager = MemoryManager(Path(tmp) / "memory.json")

            manager.append_user_memory("style", "偏好简洁回答")
            manager.append_user_memory("style", "偏好简洁回答")
            text = (Path(tmp) / "user.md").read_text(encoding="utf-8")

        self.assertIn("## 交流风格偏好", text)
        self.assertEqual(text.count("- 偏好简洁回答"), 1)

    def test_propose_soul_change_does_not_write_soul_markdown(self):
        with tempfile.TemporaryDirectory() as tmp:
            manager = MemoryManager(Path(tmp) / "memory.json")
            before = (Path(tmp) / "soul.md").read_text(encoding="utf-8")

            proposal = manager.propose_soul_change("Jarvis 核心边界", "以后不用确认直接写日程")
            after = (Path(tmp) / "soul.md").read_text(encoding="utf-8")

        self.assertEqual(before, after)
        self.assertEqual(proposal["requires_confirmation"], "true")

    def test_wal_file_is_not_managed_by_memory_editor(self):
        with tempfile.TemporaryDirectory() as tmp:
            manager = MemoryManager(Path(tmp) / "memory.json")

            with self.assertRaises(ValueError):
                manager.update_managed_file("wal", "{}\n")

    def test_unknown_managed_file_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            manager = MemoryManager(Path(tmp) / "memory.json")

            with self.assertRaises(ValueError):
                manager.update_managed_file("../user", "bad")

    def test_oversized_managed_file_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            manager = MemoryManager(Path(tmp) / "memory.json")

            with self.assertRaises(ValueError):
                manager.update_managed_file("user", "x" * (MEMORY_FILE_WRITE_LIMIT_BYTES + 1))

    def test_large_managed_file_returns_truncated_tail(self):
        with tempfile.TemporaryDirectory() as tmp:
            manager = MemoryManager(Path(tmp) / "memory.json")
            heartbeat = Path(tmp) / "heartbeat.md"
            heartbeat.write_bytes(b"a" * MEMORY_FILE_WRITE_LIMIT_BYTES + b"tail")

            file_payload = {item["id"]: item for item in manager.managed_files()}["heartbeat"]

        self.assertTrue(file_payload["truncated"])
        self.assertEqual(file_payload["byte_size"], MEMORY_FILE_WRITE_LIMIT_BYTES + 4)
        self.assertTrue(file_payload["content"].endswith("tail"))


class CronMemoryTests(unittest.TestCase):
    def test_append_list_and_delete_cron_task(self):
        with tempfile.TemporaryDirectory() as tmp:
            manager = MemoryManager(Path(tmp) / "memory.json")

            with patch.dict(sys.modules, {"croniter": SimpleNamespace(croniter=_FakeCroniter)}):
                task = append_cron_task(manager, "0 10 * * *", "做复盘", "提醒你做复盘")
                tasks = read_cron_tasks(manager)

            self.assertEqual(len(tasks), 1)
            self.assertEqual(tasks[0].id, task.id)
            self.assertEqual(tasks[0].cron_expr, "0 10 * * *")
            self.assertIn("## Cron 规则", (Path(tmp) / "heartbeat.md").read_text(encoding="utf-8"))
            self.assertTrue(delete_cron_task(manager, task.id))
            self.assertEqual(read_cron_tasks(manager), [])
            self.assertFalse(delete_cron_task(manager, task.id))

    def test_parse_legacy_cron_line(self):
        task = parse_cron_task_line("- cron: 0 10 * * * | 做复盘 | 提醒你做复盘")

        self.assertTrue(task.id.startswith("cron_"))
        self.assertEqual(task.cron_expr, "0 10 * * *")
        self.assertEqual(task.title, "做复盘")
        self.assertEqual(task.body, "提醒你做复盘")

    def test_invalid_cron_expression_is_rejected(self):
        with self.assertRaises(ValueError):
            validate_cron_expr("not a cron")

    def test_cron_validation_falls_back_when_croniter_is_missing(self):
        with patch.dict(sys.modules, {"croniter": None}):
            self.assertEqual(validate_cron_expr("49 23 * * *"), "49 23 * * *")
            previous = previous_cron_time("49 23 * * *", datetime(2026, 6, 7, 23, 49, 30))

        self.assertEqual(previous, datetime(2026, 6, 7, 23, 49, 0))

    def test_describe_cron_expression_for_common_schedules(self):
        with patch.dict(sys.modules, {"croniter": SimpleNamespace(croniter=_FakeCroniter)}):
            self.assertEqual(describe_cron_expr("20 0 * * *"), "每天 00:20")
            self.assertEqual(describe_cron_expr("0 18 * * 1-5"), "每个工作日 18:00")
            self.assertEqual(describe_cron_expr("30 9 * * 1"), "每周一 09:30")
            self.assertEqual(describe_cron_expr("0 10 1 * *"), "每月 1 日 10:00")

    def test_heartbeat_emits_cron_reminder_and_marks_seen(self):
        with tempfile.TemporaryDirectory() as tmp:
            manager = MemoryManager(Path(tmp) / "memory.json")
            with patch.dict(sys.modules, {"croniter": SimpleNamespace(croniter=_FakeCroniter)}):
                task = append_cron_task(manager, "0 10 * * *", "做复盘", "提醒你做复盘")
                engine = HeartbeatEngine(manager)

                events = engine._cron_rules(datetime(2026, 6, 7, 10, 0, 30))
                repeated = engine._cron_rules(datetime(2026, 6, 7, 10, 0, 45))

        self.assertEqual(len(events), 1)
        self.assertEqual(events[0].trigger_type, "cron_reminder")
        self.assertIn(task.id, events[0].id)
        self.assertEqual(events[0].title, "做复盘")
        self.assertEqual(repeated, [])


class CronReplyFormattingTests(unittest.TestCase):
    def test_cron_list_reply_uses_markdown_and_human_time(self):
        with tempfile.TemporaryDirectory() as tmp:
            manager = MemoryManager(Path(tmp) / "memory.json")
            app.state.agent = SimpleNamespace(memory_manager=manager)
            with patch.dict(sys.modules, {"croniter": SimpleNamespace(croniter=_FakeCroniter)}):
                task = append_cron_task(manager, "20 0 * * *", "洗澡", "每天凌晨 0:20 提醒你洗澡")
                reply = _cron_tasks_reply()

        self.assertIn("⏰ **已有 Cron 弹窗提醒**", reply)
        self.assertIn("**时间**：每天 00:20", reply)
        self.assertIn(f"**ID**：`{task.id}`", reply)
        self.assertIn("**Cron**：`20 0 * * *`", reply)


class MemoryActionExecutionTests(unittest.TestCase):
    def test_execute_memory_action_writes_user_profile(self):
        with tempfile.TemporaryDirectory() as tmp:
            manager = MemoryManager(Path(tmp) / "memory.json")
            app.state.agent = SimpleNamespace(memory_manager=manager)
            plan = AssistantActionPlan(
                action="update_memory",
                memory_actions=[
                    {
                        "tool": "set_user_profile",
                        "arguments": {"field": "preferred_name", "value": "khalil"},
                        "confidence": 0.95,
                        "requires_confirmation": False,
                    }
                ],
            )

            updates, requires_confirmation = _execute_memory_actions(plan)
            text = (Path(tmp) / "user.md").read_text(encoding="utf-8")

        self.assertFalse(requires_confirmation)
        self.assertEqual(updates[0]["field"], "preferred_name")
        self.assertIn("- 称呼偏好：khalil", text)

    def test_execute_soul_memory_action_requires_confirmation_without_write(self):
        with tempfile.TemporaryDirectory() as tmp:
            manager = MemoryManager(Path(tmp) / "memory.json")
            app.state.agent = SimpleNamespace(memory_manager=manager)
            before = (Path(tmp) / "soul.md").read_text(encoding="utf-8")
            plan = AssistantActionPlan(
                action="update_memory",
                memory_actions=[
                    {
                        "tool": "propose_soul_change",
                        "arguments": {"section": "Jarvis 核心边界", "proposal": "以后不用确认直接写日程"},
                        "confidence": 0.95,
                        "requires_confirmation": True,
                    }
                ],
            )

            updates, requires_confirmation = _execute_memory_actions(plan)
            after = (Path(tmp) / "soul.md").read_text(encoding="utf-8")

        self.assertTrue(requires_confirmation)
        self.assertEqual(before, after)
        self.assertEqual(updates[0]["tool"], "propose_soul_change")


class AssistantChatIntentTests(unittest.TestCase):
    def test_parse_generic_alert_preference(self):
        values = parse_preference_update("默认提前15min提醒")

        self.assertEqual(values["calendar_default_alert_minutes"], 15)
        self.assertEqual(values["reminder_default_alert_minutes"], 15)
        self.assertIn("Memory", preference_reply(values))
        self.assertIn("提前 15 分钟", preference_reply(values))

    def test_parse_default_reminder_time_minutes_updates_alert_preferences(self):
        values = parse_preference_update("默认提醒时间改为15min")

        self.assertEqual(values["calendar_default_alert_minutes"], 15)
        self.assertEqual(values["reminder_default_alert_minutes"], 15)

    def test_parse_scoped_default_reminder_time_minutes(self):
        values = parse_preference_update("待办默认提醒时间改为15min")

        self.assertEqual(values, {"reminder_default_alert_minutes": 15})

    def test_parse_reminder_due_time_preference(self):
        values = parse_preference_update("待办默认晚上8点提醒")

        self.assertEqual(values["reminder_default_due_time"], "20:00")

    def test_cron_command_detection(self):
        self.assertTrue(is_cron_help_request("/cron-help"))
        self.assertTrue(is_cron_list_request("/cron-list"))
        self.assertTrue(is_cron_delete_request("/cron-delete cron_abcd1234"))
        self.assertTrue(is_cron_create_request("/cron 每天上午10点提醒我做复盘"))
        self.assertEqual(cron_delete_id("/cron-delete cron_abcd1234"), "cron_abcd1234")
        self.assertEqual(cron_command_payload("/cron 每天上午10点提醒我做复盘"), "每天上午10点提醒我做复盘")

    def test_cron_planner_parses_model_json(self):
        class CronProvider:
            async def chat(self, **kwargs):
                self.kwargs = kwargs
                return json.dumps({"cron_expr": "0 10 * * *", "title": "做复盘", "body": "提醒你做复盘"})

        provider = CronProvider()
        plan = asyncio.run(plan_cron_task(provider, "/cron 每天上午10点提醒我做复盘", datetime(2026, 6, 7, 9, 0, 0)))

        self.assertEqual(plan["cron_expr"], "0 10 * * *")
        self.assertEqual(plan["title"], "做复盘")
        self.assertIn("5 字段 cron", provider.kwargs["system_prompt"])

    def test_memory_update_request_detection(self):
        self.assertTrue(is_memory_update_request("以后称呼我为 khalil"))
        self.assertTrue(is_memory_update_request("记住我偏好简洁回答"))
        self.assertTrue(is_memory_update_request("我叫 khalil"))
        self.assertTrue(is_memory_update_request("我在上海"))
        self.assertTrue(is_memory_update_request("我的城市是上海"))
        self.assertFalse(is_memory_update_request("我今天有点累"))
        self.assertFalse(is_memory_update_request("我在开会"))
        self.assertFalse(is_memory_update_request("默认提醒时间改为15min"))
        self.assertFalse(is_memory_update_request("我叫什么"))
        self.assertFalse(is_memory_update_request("我在哪里"))
        self.assertFalse(is_memory_update_request("你知道我的名字吗"))

    def test_profile_update_parser_extracts_city_statement(self):
        self.assertEqual(parse_profile_update("我在上海"), {"field": "city", "value": "上海"})
        self.assertEqual(parse_profile_update("我住在北京"), {"field": "city", "value": "北京"})
        self.assertEqual(parse_profile_update("我叫 Khalil"), {"field": "preferred_name", "value": "Khalil"})
        self.assertIsNone(parse_profile_update("我在哪里"))
        self.assertIsNone(parse_profile_update("我在开会"))

    def test_planner_profile_statement_overrides_chat_plan(self):
        class ChatProvider:
            async def chat(self, **kwargs):
                return json.dumps({"action": "chat", "reply": "好的，我记住了。"})

        plan = asyncio.run(
            plan_assistant_action(
                ChatProvider(),
                "我在上海",
                [],
                datetime(2026, 6, 8, 10, 0, 0),
            )
        )

        self.assertEqual(plan.action, "update_memory")
        self.assertEqual(plan.memory_actions[0].tool, "set_user_profile")
        self.assertEqual(plan.memory_actions[0].arguments["field"], "city")
        self.assertEqual(plan.memory_actions[0].arguments["value"], "上海")
        self.assertFalse(plan.confirmation_required)

    def test_assistant_chat_falls_back_to_plain_chat_when_planner_returns_invalid_json(self):
        class InvalidPlannerProvider:
            def __init__(self):
                self.calls = []

            async def chat(self, **kwargs):
                self.calls.append(kwargs)
                if len(self.calls) == 1:
                    return "not json"
                return "这是普通聊天回复。"

        provider = InvalidPlannerProvider()
        previous_agent = getattr(app.state, "agent", None)
        previous_provider = getattr(app.state, "active_provider", None)
        previous_provider_id = getattr(app.state, "active_provider_id", None)
        previous_model_id = getattr(app.state, "active_model_id", None)
        previous_sessions = getattr(app.state, "assistant_sessions", None)
        try:
            with tempfile.TemporaryDirectory() as tmp:
                app.state.agent = SimpleNamespace(memory_manager=MemoryManager(Path(tmp) / "memory.json"))
                app.state.active_provider = provider
                app.state.active_provider_id = "test"
                app.state.active_model_id = "test"
                app.state.assistant_sessions = {}

                response = asyncio.run(
                    assistant_chat(
                        AssistantChatRequest(message="查看最近2天日程", session_id="planner-fallback-test")
                    )
                )
        finally:
            app.state.agent = previous_agent
            app.state.active_provider = previous_provider
            app.state.active_provider_id = previous_provider_id
            app.state.active_model_id = previous_model_id
            app.state.assistant_sessions = previous_sessions

        self.assertEqual(response.action, "chat")
        self.assertEqual(response.reply, "这是普通聊天回复。")
        self.assertEqual(len(provider.calls), 2)

    def test_planner_accepts_memory_action_plan(self):
        class MemoryProvider:
            async def chat(self, **kwargs):
                self.kwargs = kwargs
                return json.dumps(
                    {
                        "action": "update_memory",
                        "reply": "好的，以后我称呼你为 khalil。",
                        "memory_actions": [
                            {
                                "tool": "set_user_profile",
                                "arguments": {"field": "preferred_name", "value": "khalil"},
                                "confidence": 0.96,
                                "requires_confirmation": False,
                            }
                        ],
                        "confirmation_required": False,
                    }
                )

        provider = MemoryProvider()
        plan = asyncio.run(
            plan_assistant_action(
                provider,
                "以后称呼我为 khalil",
                [],
                datetime(2026, 6, 8, 10, 0, 0),
            )
        )

        self.assertEqual(plan.action, "update_memory")
        self.assertEqual(plan.memory_actions[0].tool, "set_user_profile")
        self.assertEqual(plan.memory_actions[0].arguments["field"], "preferred_name")
        self.assertFalse(plan.confirmation_required)
        self.assertIn("update_memory", provider.kwargs["system_prompt"])

    def test_soul_memory_action_requires_confirmation(self):
        class SoulProvider:
            async def chat(self, **kwargs):
                return json.dumps(
                    {
                        "action": "update_memory",
                        "reply": "这会修改核心边界，需要你确认。",
                        "memory_actions": [
                            {
                                "tool": "propose_soul_change",
                                "arguments": {"section": "Jarvis 核心边界", "proposal": "以后不用确认直接写日程"},
                                "confidence": 0.9,
                                "requires_confirmation": True,
                            }
                        ],
                    }
                )

        plan = asyncio.run(
            plan_assistant_action(
                SoulProvider(),
                "修改你的边界，以后不用确认直接写日程",
                [],
                datetime(2026, 6, 8, 10, 0, 0),
            )
        )

        self.assertEqual(plan.action, "update_memory")
        self.assertTrue(plan.confirmation_required)

    def test_preference_parser_overrides_incomplete_model_preference_plan(self):
        class CalendarOnlyPreferenceProvider:
            async def chat(self, **kwargs):
                return json.dumps(
                    {
                        "action": "update_preference",
                        "reply": "好的，已更新默认日程提醒为提前 20 分钟。",
                        "preference_values": {"calendar_default_alert_minutes": "20"},
                        "confirmation_required": False,
                    }
                )

        plan = asyncio.run(
            plan_assistant_action(
                CalendarOnlyPreferenceProvider(),
                "默认的提醒时间为提前20min",
                [],
                datetime(2026, 6, 7, 10, 0, 0),
            )
        )

        self.assertEqual(plan.action, "update_preference")
        self.assertEqual(plan.preference_values["calendar_default_alert_minutes"], 20)
        self.assertEqual(plan.preference_values["reminder_default_alert_minutes"], 20)
        self.assertIn("待办默认提前提醒", plan.reply)

    def test_calendar_and_list_are_not_user_preferences(self):
        self.assertIsNone(parse_preference_update("默认日历设为 Work"))
        self.assertIsNone(parse_preference_update("默认提醒列表设为 Life"))

    def test_schedule_request_detection(self):
        self.assertTrue(is_schedule_request("帮我明天下午三点加个会"))
        self.assertTrue(is_schedule_request("明天下午3点开会，大概持续1小时，提前30min提醒我"))
        self.assertFalse(is_schedule_request("默认提前15分钟提醒"))
        self.assertFalse(is_schedule_request("你好，今天怎么样"))

    def test_schedule_creation_request_detection_is_narrower_than_schedule_reference(self):
        self.assertTrue(is_schedule_creation_request("添加日程，明天晚上6点30项目管理答辩，大概1小时，提前30min提醒我"))
        self.assertTrue(is_schedule_creation_request("明天下午3点开会，大概持续1小时，提前30min提醒我"))
        self.assertTrue(is_schedule_creation_request("今天上午10点我要参加视频会议"))
        self.assertFalse(is_schedule_creation_request("查看未来2天日程"))
        self.assertFalse(is_schedule_creation_request("今天上午10点的视频会议在哪里"))
        self.assertFalse(is_schedule_creation_request("今晚9点的开会提前20min提醒我"))

    def test_local_operation_detection(self):
        self.assertTrue(is_local_operation_request("列出明天的日程/待办"))
        self.assertTrue(is_local_operation_request("删除明天的开会日程"))
        self.assertTrue(is_local_operation_request("把明天下午开会日程推迟1小时开始"))
        self.assertTrue(is_local_operation_request("最近2天的日程和待办"))
        self.assertTrue(is_local_operation_request("2天内的日程"))
        self.assertFalse(is_local_operation_request("明天下午3点开会，大概持续1小时，提前30min提醒我"))
        self.assertFalse(is_local_operation_request("默认提前15分钟提醒"))

    def test_new_calendar_with_alert_is_not_existing_alert_update(self):
        plan = heuristic_action_plan("明天下午3点开会，大概持续1小时，提前30min提醒我", datetime(2026, 6, 7, 10, 0, 0))

        self.assertIsNone(plan)

    def test_heuristic_plan_lists_tomorrow_items(self):
        plan = heuristic_action_plan("列出明天的日程/待办", datetime(2026, 6, 7, 10, 0, 0))

        self.assertEqual(plan.action, "list_items")
        self.assertEqual(plan.target.item_kind, "both")
        self.assertEqual(plan.target.date_range.start_date, "2026-06-08")
        self.assertEqual(plan.target.date_range.end_date, "2026-06-09")

    def test_heuristic_plan_lists_implicit_recent_items(self):
        plan = heuristic_action_plan("最近2天的日程和待办", datetime(2026, 6, 7, 10, 0, 0))

        self.assertEqual(plan.action, "list_items")
        self.assertEqual(plan.target.item_kind, "both")
        self.assertEqual(plan.target.title_keywords, [])
        self.assertEqual(plan.target.date_range.start_date, "2026-06-07")
        self.assertEqual(plan.target.date_range.end_date, "2026-06-09")

    def test_list_queries_always_include_calendar_and_reminders(self):
        now = datetime(2026, 6, 7, 10, 0, 0)

        calendar_plan = heuristic_action_plan("查看最近2天日程", now)
        reminder_plan = heuristic_action_plan("查看最近2天待办", now)

        self.assertEqual(calendar_plan.action, "list_items")
        self.assertEqual(calendar_plan.target.item_kind, "both")
        self.assertEqual(calendar_plan.target.title_keywords, [])
        self.assertEqual(calendar_plan.target.date_range.start_date, "2026-06-07")
        self.assertEqual(calendar_plan.target.date_range.end_date, "2026-06-09")
        self.assertEqual(reminder_plan.action, "list_items")
        self.assertEqual(reminder_plan.target.item_kind, "both")
        self.assertEqual(reminder_plan.target.title_keywords, [])
        self.assertEqual(reminder_plan.target.date_range.start_date, "2026-06-07")
        self.assertEqual(reminder_plan.target.date_range.end_date, "2026-06-09")

    def test_list_queries_accept_chinese_day_count(self):
        plan = heuristic_action_plan("查看最近两天日程", datetime(2026, 6, 7, 10, 0, 0))

        self.assertEqual(plan.action, "list_items")
        self.assertEqual(plan.target.item_kind, "both")
        self.assertEqual(plan.target.title_keywords, [])
        self.assertEqual(plan.target.date_range.start_date, "2026-06-07")
        self.assertEqual(plan.target.date_range.end_date, "2026-06-09")

    def test_heuristic_plan_lists_future_calendar_and_reminders_with_slash(self):
        plan = heuristic_action_plan("查看未来2天的日程/提醒事项", datetime(2026, 6, 7, 10, 0, 0))

        self.assertEqual(plan.action, "list_items")
        self.assertEqual(plan.target.item_kind, "both")
        self.assertEqual(plan.target.title_keywords, [])
        self.assertEqual(plan.target.date_range.start_date, "2026-06-07")
        self.assertEqual(plan.target.date_range.end_date, "2026-06-09")

    def test_list_command_defaults_to_calendar_and_reminders(self):
        plan = heuristic_action_plan("/list 未来2天", datetime(2026, 6, 7, 10, 0, 0))

        self.assertEqual(plan.action, "list_items")
        self.assertEqual(plan.target.item_kind, "both")
        self.assertEqual(plan.target.title_keywords, [])
        self.assertEqual(plan.target.date_range.start_date, "2026-06-07")
        self.assertEqual(plan.target.date_range.end_date, "2026-06-09")

    def test_list_command_ignores_command_words_and_separators(self):
        plan = heuristic_action_plan("/list 看一下未来2天日程/提醒事项", datetime(2026, 6, 7, 10, 0, 0))

        self.assertEqual(plan.action, "list_items")
        self.assertEqual(plan.target.item_kind, "both")
        self.assertEqual(plan.target.title_keywords, [])
        self.assertEqual(plan.target.date_range.start_date, "2026-06-07")
        self.assertEqual(plan.target.date_range.end_date, "2026-06-09")

    def test_slash_list_week_ranges(self):
        now = datetime(2026, 6, 7, 10, 0, 0)
        cases = [
            ("/list 未来1周", "2026-06-07", "2026-06-14"),
            ("/list 未来一周", "2026-06-07", "2026-06-14"),
            ("/list 最近2周", "2026-06-07", "2026-06-21"),
            ("/list 接下来一个星期", "2026-06-07", "2026-06-14"),
        ]
        for msg, expected_start, expected_end in cases:
            with self.subTest(msg=msg):
                plan = heuristic_action_plan(msg, now)
                self.assertEqual(plan.action, "list_items", msg)
                self.assertEqual(plan.target.date_range.start_date, expected_start, msg)
                self.assertEqual(plan.target.date_range.end_date, expected_end, msg)

    def test_slash_list_month_ranges(self):
        now = datetime(2026, 6, 7, 10, 0, 0)
        cases = [
            ("/list 未来一个月", "2026-06-07", "2026-07-07"),
            ("/list 最近2个月", "2026-06-07", "2026-08-06"),
        ]
        for msg, expected_start, expected_end in cases:
            with self.subTest(msg=msg):
                plan = heuristic_action_plan(msg, now)
                self.assertEqual(plan.action, "list_items", msg)
                self.assertEqual(plan.target.date_range.start_date, expected_start, msg)
                self.assertEqual(plan.target.date_range.end_date, expected_end, msg)

    def test_contextual_future_range_answer_continues_list_operation(self):
        history = [
            {"role": "user", "content": "列出最近2天日程"},
            {"role": "assistant", "content": "您是想查看最近2天已经过去的日程，还是未来2天的日程？"},
        ]

        self.assertTrue(is_contextual_local_operation_request("未来2天", history))
        plan = heuristic_contextual_action_plan("未来2天", history, datetime(2026, 6, 7, 10, 0, 0))

        self.assertEqual(plan.action, "list_items")
        self.assertEqual(plan.target.item_kind, "both")
        self.assertEqual(plan.target.title_keywords, [])
        self.assertEqual(plan.target.date_range.start_date, "2026-06-07")
        self.assertEqual(plan.target.date_range.end_date, "2026-06-09")

    def test_planner_respects_model_for_non_slash_list_requests(self):
        class ChatOnlyProvider:
            async def chat(self, **kwargs):
                return json.dumps({"action": "chat", "reply": "我无法直接读取你的系统日历。"})

        plan = asyncio.run(
            plan_assistant_action(
                ChatOnlyProvider(),
                "最近2天的日程和待办",
                [],
                datetime(2026, 6, 7, 10, 0, 0),
            )
        )

        self.assertEqual(plan.action, "chat")

    def test_new_schedule_creation_uses_extraction_route_not_local_operation_route(self):
        text = "明天下午3点开会，大概持续1小时，提前30min提醒我"

        self.assertTrue(is_schedule_request(text))
        self.assertTrue(is_schedule_creation_request(text))
        self.assertFalse(is_local_operation_request(text))
        self.assertFalse(is_slash_list_request(text))

    def test_add_schedule_with_alert_uses_extraction_route(self):
        text = "添加日程，明天晚上6点30项目管理答辩，大概1小时，提前30min提醒我"

        self.assertTrue(is_schedule_request(text))
        self.assertTrue(is_schedule_creation_request(text))
        self.assertFalse(is_local_operation_request(text))
        self.assertFalse(is_slash_list_request(text))

    def test_new_schedule_with_alert_uses_extraction_route(self):
        text = "新建日程，明天晚上6点半项目管理答辩，提前30分钟提醒我"

        self.assertTrue(is_schedule_request(text))
        self.assertTrue(is_schedule_creation_request(text))
        self.assertFalse(is_local_operation_request(text))
        self.assertFalse(is_slash_list_request(text))

    def test_confirmation_reply_reuses_previous_creation_context(self):
        history = [
            {"role": "user", "content": "明天（6月8日）下午4点到5点答辩，提前20分钟提醒，对吗？"},
            {
                "role": "assistant",
                "content": "需要你最后确认一次：明天（6月8日）下午4点到5点答辩，提前20分钟提醒，是否确认添加？",
            },
        ]

        text = contextual_schedule_creation_text("确认添加", history)

        self.assertIsNotNone(text)
        self.assertIn("下午4点到5点答辩", text)
        self.assertIn("用户确认：确认添加", text)

    def test_confirmation_reply_without_creation_context_is_not_schedule_creation(self):
        history = [
            {"role": "user", "content": "hello"},
            {"role": "assistant", "content": "你好，有什么可以帮你的？"},
        ]

        self.assertIsNone(contextual_schedule_creation_text("确认添加", history))

    def test_heuristic_plan_deletes_calendar_target(self):
        plan = heuristic_action_plan("删除明天的开会日程", datetime(2026, 6, 7, 10, 0, 0))

        self.assertEqual(plan.action, "delete_items")
        self.assertEqual(plan.target.item_kind, "calendar")
        self.assertIn("开会", plan.target.title_keywords)
        self.assertTrue(plan.confirmation_required)

    def test_heuristic_plan_reschedules_with_shift(self):
        plan = heuristic_action_plan("把明天下午开会日程推迟1小时开始", datetime(2026, 6, 7, 10, 0, 0))

        self.assertEqual(plan.action, "reschedule_item")
        self.assertEqual(plan.target.item_kind, "calendar")
        self.assertEqual(plan.patch.shift_minutes, 60)
        self.assertTrue(plan.confirmation_required)

    def test_heuristic_plan_reschedules_weekday_evening_event_with_time(self):
        plan = heuristic_action_plan("周日晚上22点的会议提前了1小时", datetime(2026, 6, 7, 17, 30, 0))

        self.assertEqual(plan.action, "reschedule_item")
        self.assertEqual(plan.target.item_kind, "calendar")
        self.assertEqual(plan.target.title_keywords, ["会议"])
        self.assertEqual(plan.target.date_range.start_date, "2026-06-07")
        self.assertEqual(plan.target.date_range.end_date, "2026-06-08")
        self.assertEqual(plan.target.time_of_day, "22:00")
        self.assertEqual(plan.target.time_period, "evening")
        self.assertEqual(plan.patch.shift_minutes, -60)
        self.assertTrue(plan.confirmation_required)

    def test_heuristic_plan_reschedules_today_evening_event_without_exact_time(self):
        plan = heuristic_action_plan("今天晚上的会议提前了一小时", datetime(2026, 6, 7, 17, 30, 0))

        self.assertEqual(plan.action, "reschedule_item")
        self.assertEqual(plan.target.item_kind, "calendar")
        self.assertEqual(plan.target.title_keywords, ["会议"])
        self.assertEqual(plan.target.date_range.start_date, "2026-06-07")
        self.assertIsNone(plan.target.time_of_day)
        self.assertEqual(plan.target.time_period, "evening")
        self.assertEqual(plan.patch.shift_minutes, -60)

    def test_heuristic_plan_reschedules_with_chinese_time(self):
        plan = heuristic_action_plan("今晚十点的会议提前一小时", datetime(2026, 6, 7, 17, 30, 0))

        self.assertEqual(plan.action, "reschedule_item")
        self.assertEqual(plan.target.time_of_day, "22:00")
        self.assertEqual(plan.patch.shift_minutes, -60)

    def test_heuristic_plan_updates_existing_calendar_alert(self):
        plan = heuristic_action_plan("今晚9点的开会提前20min提醒我", datetime(2026, 6, 7, 10, 0, 0))

        self.assertEqual(plan.action, "update_alert")
        self.assertEqual(plan.target.item_kind, "calendar")
        self.assertEqual(plan.target.title_keywords, ["开会"])
        self.assertEqual(plan.target.date_range.start_date, "2026-06-07")
        self.assertEqual(plan.target.time_of_day, "21:00")
        self.assertEqual(plan.patch.alert_minutes_before, 20)
        self.assertFalse(plan.confirmation_required)

    def test_heuristic_plan_updates_existing_calendar_alert_with_chinese_time(self):
        self.assertTrue(is_local_operation_request("今晚九点的开会提前20min提醒我"))

    def test_explicit_reminder_word_updates_alert_not_schedule(self):
        plan = heuristic_action_plan("今天晚上22点的会议提醒提前了1小时", datetime(2026, 6, 7, 17, 30, 0))

        self.assertEqual(plan.action, "update_alert")
        self.assertEqual(plan.target.item_kind, "calendar")
        self.assertEqual(plan.target.title_keywords, ["会议"])
        self.assertEqual(plan.target.time_of_day, "22:00")
        self.assertEqual(plan.patch.alert_minutes_before, 60)
        self.assertFalse(plan.confirmation_required)

    def test_heuristic_plan_clarifies_missing_reschedule_patch(self):
        plan = heuristic_action_plan("修改明天的开会日程", datetime(2026, 6, 7, 10, 0, 0))

        self.assertEqual(plan.action, "clarify")
        self.assertIn("什么时候", plan.clarification_question)

    def test_assistant_extraction_session_ids_are_unique(self):
        first = _assistant_extraction_session_id("chat-session")
        second = _assistant_extraction_session_id("chat-session")

        self.assertTrue(first.startswith("assistant:chat-session:"))
        self.assertTrue(second.startswith("assistant:chat-session:"))
        self.assertNotEqual(first, second)


class ToolSchemaTests(unittest.TestCase):
    def test_tool_lists_include_batch_extraction_and_no_event(self):
        anthropic_tools = get_anthropic_tools()
        openai_tools = get_openai_tools()

        self.assertEqual(
            [tool["name"] for tool in anthropic_tools],
            ["extract_schedule_items", "no_event"],
        )
        self.assertEqual(
            [tool["function"]["name"] for tool in openai_tools],
            ["extract_schedule_items", "no_event"],
        )

    def test_schema_constraints_document_defaults(self):
        tools = {tool["name"]: tool for tool in get_anthropic_tools()}
        candidate = tools["extract_schedule_items"]["input_schema"]["properties"]["candidates"]["items"]
        reminder_props = candidate["properties"]["reminder"]["properties"]
        calendar_props = candidate["properties"]["calendar"]["properties"]

        self.assertEqual(reminder_props["priority"]["enum"], ["none", "low", "medium", "high"])
        self.assertEqual(reminder_props["alert_minutes_before_due"]["minimum"], 0)
        self.assertEqual(calendar_props["alert_minutes_before_start"]["minimum"], 0)
        self.assertEqual(calendar_props["recurrence"]["properties"]["interval"]["minimum"], 1)
        self.assertIn("clarification_question", candidate["properties"])


class LocalModelRegistryTests(unittest.TestCase):
    def test_safe_model_id_handles_huggingface_repo_ids(self):
        self.assertEqual(
            safe_model_id("mlx-community/Qwen2.5-3B-Instruct-4bit"),
            "mlx-community--Qwen2.5-3B-Instruct-4bit",
        )

    def test_registry_writes_lists_gets_and_deletes_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            registry = LocalModelRegistry(Path(tmp))
            manifest = registry.build_manifest("mlx-community/Test-Model", display_name="Test Model")
            registry.write_manifest(manifest)

            models = registry.list_models()
            loaded = registry.get_model(manifest["id"])

            self.assertEqual(len(models), 1)
            self.assertEqual(models[0]["repo_id"], "mlx-community/Test-Model")
            self.assertEqual(loaded["display_name"], "Test Model")
            self.assertFalse(loaded["supports_vision"])

            registry.delete_model(manifest["id"])
            self.assertEqual(registry.list_models(), [])


class APIKeyConfigTests(unittest.TestCase):
    def test_masks_key_with_middle_omitted(self):
        self.assertEqual(_mask_secret("sk-1234567890"), "sk-123**7890")

    def test_normalizes_legacy_single_key_config(self):
        provider_cfg = {"api_key": "sk-legacy", "model_id": "deepseek-chat"}

        keys, active_id = _normalize_api_keys(provider_cfg)

        self.assertEqual(len(keys), 1)
        self.assertEqual(keys[0]["api_key"], "sk-legacy")
        self.assertEqual(active_id, keys[0]["id"])
        self.assertEqual(_active_api_key(provider_cfg), "sk-legacy")

    def test_upsert_and_switch_active_key(self):
        provider_cfg = {}
        first_id = _upsert_api_key(provider_cfg, "sk-first")
        second_id = _upsert_api_key(provider_cfg, "sk-second")

        self.assertNotEqual(first_id, second_id)
        self.assertEqual(_active_api_key(provider_cfg), "sk-second")

        selected = _set_active_api_key(provider_cfg, first_id)

        self.assertEqual(selected, "sk-first")
        self.assertEqual(provider_cfg["active_api_key_id"], first_id)
        self.assertEqual(_active_api_key(provider_cfg), "sk-first")


class PromptTests(unittest.TestCase):
    def test_prompt_includes_vision_mode_context(self):
        prompt = build_system_prompt(MemoryManager(Path(tempfile.gettempdir()) / "missing-memory.json"), "vision")

        self.assertIn("输入模式：截图图片", prompt)
        self.assertIn("Calendar 字段规则", prompt)

    def test_prompt_includes_ocr_mode_context(self):
        prompt = build_system_prompt(MemoryManager(Path(tempfile.gettempdir()) / "missing-memory.json"), "ocr_text")

        self.assertIn("输入模式：截图 OCR 文本", prompt)
        self.assertIn("OCR 可能有错字", prompt)

    def test_prompt_includes_user_text_mode_context(self):
        prompt = build_system_prompt(MemoryManager(Path(tempfile.gettempdir()) / "missing-memory.json"), "user_text")

        self.assertIn("输入模式：用户直接文本", prompt)

    def test_prompt_current_time_includes_local_timezone_offset(self):
        prompt = build_system_prompt(MemoryManager(Path(tempfile.gettempdir()) / "missing-memory.json"), "user_text")

        self.assertRegex(prompt, r"当前时间：\d{4}-\d{2}-\d{2} \d{2}:\d{2} [+-]\d{4} \([^)]+, [^)]+\)")

    def test_prompt_documents_calendar_reminder_boundary_examples(self):
        prompt = build_system_prompt(MemoryManager(Path(tempfile.gettempdir()) / "missing-memory.json"), "user_text")

        self.assertIn("明天记得交电费", prompt)
        self.assertIn("missing_fields 包含 time", prompt)
        self.assertIn("不要自动填 09:00", prompt)
        self.assertIn("周六考试", prompt)
        self.assertIn("周六前报名考试", prompt)
        self.assertIn("开会前发一下议程", prompt)
        self.assertIn("clarification_question", prompt)

    def test_prompt_does_not_treat_template_reminder_time_as_learned_preference(self):
        with tempfile.TemporaryDirectory() as tmp:
            prompt = build_system_prompt(MemoryManager(Path(tmp) / "memory.json"), "user_text")

        self.assertIn("提醒默认到期时间：未学习稳定偏好，缺具体时间时追问用户", prompt)

    def test_prompt_includes_explicit_reminder_time_preference(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "memory.json"
            path.write_text(json.dumps({"preferences": {"reminder_default_due_time": "18:30"}}), encoding="utf-8")

            prompt = build_system_prompt(MemoryManager(path), "user_text")

        self.assertIn("提醒默认到期时间：18:30", prompt)

    def test_invalid_input_mode_falls_back_to_user_text(self):
        self.assertEqual(normalize_input_mode("unknown"), "user_text")


class ResultTests(unittest.TestCase):
    def test_calendar_result_matches_chat_response_fields(self):
        result = normalize_tool_result(
            "create_calendar_event",
            {
                "title": "Meeting",
                "start_time": "2026-05-06T10:00:00",
                "end_time": "2026-05-06T11:00:00",
                "location": "Office",
                "notes": "Bring notes",
            },
        )

        self.assertEqual(result["type"], "batch")
        candidate = result["candidates"][0]
        self.assertEqual(candidate["kind"], "calendar")
        self.assertEqual(candidate["calendar"]["title"], "Meeting")
        self.assertFalse(candidate["calendar"]["needs_duration"])
        self.assertEqual(candidate["calendar"]["location"], "Office")
        self.assertEqual(candidate["calendar"]["alert_minutes_before_start"], 10)
        self.assertIsNone(candidate["reminder"])

    def test_reminder_result_matches_chat_response_fields(self):
        result = normalize_tool_result(
            "create_reminder",
            {"title": "Submit", "due_date": "2026-05-07", "due_time": "09:00"},
        )

        self.assertEqual(result["type"], "batch")
        candidate = result["candidates"][0]
        self.assertEqual(candidate["kind"], "reminder")
        self.assertEqual(candidate["reminder"]["title"], "Submit")
        self.assertEqual(candidate["reminder"]["priority"], "none")
        self.assertEqual(candidate["reminder"]["list_name"], "提醒事项")
        self.assertFalse(candidate["reminder"]["flagged"])
        self.assertIsNone(candidate["calendar"])

    def test_no_event_result_matches_chat_response_fields(self):
        result = normalize_tool_result("no_event", {"reply": "没有事件"})

        self.assertEqual(result["type"], "none")
        self.assertEqual(result["reply"], "没有事件")

    def test_extract_items_preserves_clarification_question(self):
        result = normalize_tool_result(
            "extract_schedule_items",
            {
                "candidates": [
                    {
                        "kind": "calendar",
                        "calendar": {"title": "Team meeting", "start_time": "2026-05-06"},
                        "missing_fields": ["time", "duration"],
                        "clarification_question": "几点开始？预计持续多久？",
                    }
                ]
            },
        )

        candidate = result["candidates"][0]
        self.assertEqual(candidate["clarification_question"], "几点开始？预计持续多久？")


class ResultValidationTests(unittest.TestCase):
    def test_calendar_missing_end_time_sets_needs_duration(self):
        result = validate_agent_result(
            {
                "type": "calendar",
                "calendar": {
                    "title": "Team meeting",
                    "start_time": "2026-05-06T10:00:00",
                },
            }
        )

        self.assertIsNone(result["calendar"]["end_time"])
        self.assertTrue(result["calendar"]["needs_duration"])
        self.assertEqual(result["calendar"]["alert_minutes_before_start"], 10)

    def test_calendar_missing_start_time_is_invalid(self):
        with self.assertRaises(AgentValidationError):
            validate_agent_result({"type": "calendar", "calendar": {"title": "Team meeting"}})

    def test_calendar_end_before_start_is_invalid(self):
        with self.assertRaises(AgentValidationError):
            validate_agent_result(
                {
                    "type": "calendar",
                    "calendar": {
                        "title": "Team meeting",
                        "start_time": "2026-05-06T11:00:00",
                        "end_time": "2026-05-06T10:00:00",
                    },
                }
            )

    def test_calendar_accepts_timezone_datetime(self):
        result = validate_agent_result(
            {
                "type": "calendar",
                "calendar": {
                    "title": "Remote meeting",
                    "start_time": "2026-05-06T10:00:00Z",
                    "end_time": "2026-05-06T11:00:00Z",
                },
            }
        )

        self.assertFalse(result["calendar"]["needs_duration"])

    def test_batch_calendar_date_only_start_needs_input(self):
        result = validate_agent_result(
            {
                "type": "batch",
                "candidates": [
                    {
                        "kind": "calendar",
                        "calendar": {
                            "title": "Team meeting",
                            "start_time": "2026-05-06",
                            "is_all_day": False,
                        },
                    }
                ],
            }
        )

        candidate = result["candidates"][0]
        self.assertEqual(candidate["status"], "needs_input")
        self.assertIn("time", candidate["missing_fields"])
        self.assertIn("duration", candidate["missing_fields"])
        self.assertEqual(candidate["calendar"]["start_time"], "2026-05-06")
        self.assertEqual(candidate["clarification_question"], "几点开始？预计持续多久？")

    def test_invalid_reminder_priority_is_invalid(self):
        with self.assertRaises(AgentValidationError):
            validate_agent_result(
                {
                    "type": "reminder",
                    "reminder": {
                        "title": "Submit",
                        "priority": "urgent",
                    },
                }
            )


class MockProvider:
    def __init__(self, result):
        self.result = result
        self.last_call = None
        self.calls = []

    async def chat_with_tools(self, **kwargs):
        self.last_call = kwargs
        self.calls.append(kwargs)
        return self.result


class SequenceProvider:
    def __init__(self, results):
        self.results = list(results)
        self.calls = []
        self.last_call = None

    async def chat_with_tools(self, **kwargs):
        self.last_call = kwargs
        self.calls.append(kwargs)
        idx = min(len(self.calls) - 1, len(self.results) - 1)
        return self.results[idx]


class FakeCompletions:
    def __init__(self, responses):
        self.responses = list(responses)
        self.calls = []

    async def create(self, **kwargs):
        self.calls.append(kwargs)
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response


def fake_chat_response(message):
    return SimpleNamespace(choices=[SimpleNamespace(message=message)])


def fake_tool_message(tool_name: str, args: dict):
    return SimpleNamespace(
        content=None,
        tool_calls=[
            SimpleNamespace(
                function=SimpleNamespace(
                    name=tool_name,
                    arguments=json.dumps(args),
                )
            )
        ],
    )


class OpenAICompatProviderTests(unittest.IsolatedAsyncioTestCase):
    def test_deepseek_factory_disables_required_tool_choice(self):
        provider = create_provider("deepseek", {"api_key": "key", "model": "deepseek-v4-pro"})

        self.assertIsInstance(provider, OpenAICompatProvider)
        self.assertFalse(provider.supports_required_tool_choice)

    async def test_retries_without_required_tool_choice_when_provider_rejects_it(self):
        completions = FakeCompletions(
            [
                Exception("Thinking mode does not support this tool_choice"),
                fake_chat_response(
                    fake_tool_message(
                        "extract_schedule_items",
                        {
                            "candidates": [
                                {
                                    "kind": "reminder",
                                    "reminder": {"title": "Submit report"},
                                }
                            ]
                        },
                    )
                ),
            ]
        )
        provider = OpenAICompatProvider("key", "http://example.test/v1", "deepseek-v4-flash")
        provider.client = SimpleNamespace(chat=SimpleNamespace(completions=completions))

        result = await provider.chat_with_tools(
            messages=[{"role": "user", "content": "submit report"}],
            tools_openai=[{"type": "function", "function": {"name": "extract_schedule_items"}}],
        )

        self.assertEqual(result["type"], "batch")
        self.assertEqual(result["candidates"][0]["reminder"]["title"], "Submit report")
        self.assertEqual(completions.calls[0]["tool_choice"], "required")
        self.assertNotIn("tool_choice", completions.calls[1])

    async def test_skips_required_tool_choice_when_disabled(self):
        completions = FakeCompletions(
            [
                fake_chat_response(
                    fake_tool_message(
                        "extract_schedule_items",
                        {
                            "candidates": [
                                {
                                    "kind": "reminder",
                                    "reminder": {"title": "Submit report"},
                                }
                            ]
                        },
                    )
                )
            ]
        )
        provider = OpenAICompatProvider(
            "key",
            "http://example.test/v1",
            "deepseek-v4-flash",
            supports_required_tool_choice=False,
        )
        provider.client = SimpleNamespace(chat=SimpleNamespace(completions=completions))

        result = await provider.chat_with_tools(
            messages=[{"role": "user", "content": "submit report"}],
            tools_openai=[{"type": "function", "function": {"name": "extract_schedule_items"}}],
        )

        self.assertEqual(result["type"], "batch")
        self.assertEqual(len(completions.calls), 1)
        self.assertNotIn("tool_choice", completions.calls[0])


class AgentRunTests(unittest.IsolatedAsyncioTestCase):
    async def test_no_provider_result_is_unchanged(self):
        result = await JarvisAgent().run("hello")

        self.assertEqual(result["type"], "error")
        self.assertEqual(result["error"], "no_provider")
        self.assertEqual(result["reply"], "请先配置 API")

    async def test_provider_result_passes_through_with_split_components(self):
        provider = MockProvider(
            {
                "type": "batch",
                "candidates": [
                    {
                        "id": "candidate_1",
                        "kind": "reminder",
                        "reminder": {
                            "title": "Submit paper",
                            "due_date": "2026-05-07",
                            "priority": "high",
                        },
                    }
                ],
            }
        )

        result = await JarvisAgent().run("交论文", provider=provider)

        self.assertEqual(result["type"], "batch")
        self.assertEqual(result["candidates"][0]["reminder"]["title"], "Submit paper")
        self.assertIn("用户偏好", provider.last_call["system_prompt"])
        self.assertEqual(len(provider.last_call["tools"]), 2)
        self.assertEqual(len(provider.last_call["tools_openai"]), 2)

    async def test_followup_uses_pending_session_context(self):
        provider = SequenceProvider(
            [
                {
                    "type": "batch",
                    "candidates": [
                        {
                            "id": "candidate_1",
                            "kind": "calendar",
                            "calendar": {
                                "title": "Team meeting",
                                "start_time": "2026-05-06",
                            },
                        }
                    ],
                },
                {
                    "type": "batch",
                    "candidates": [
                        {
                            "id": "candidate_1",
                            "kind": "calendar",
                            "calendar": {
                                "title": "Team meeting",
                                "start_time": "2026-05-06T10:00:00",
                                "end_time": "2026-05-06T11:00:00",
                            },
                        }
                    ],
                },
            ]
        )
        with tempfile.TemporaryDirectory() as tmp:
            agent = JarvisAgent(MemoryManager(Path(tmp) / "memory.json"))
            first = await agent.run("明天开会", session_id="s1", provider=provider)
            second = await agent.run("上午10点，时长一小时", session_id="s1", provider=provider)

        self.assertEqual(first["candidates"][0]["status"], "needs_input")
        self.assertEqual(second["candidates"][0]["calendar"]["end_time"], "2026-05-06T11:00:00")
        followup_message = provider.calls[1]["messages"][0]["content"]
        self.assertIn("单个日程/待办 event", followup_message)
        self.assertIn("current_events", followup_message)
        self.assertIn("Team meeting", followup_message)
        self.assertIn("上午10点，时长一小时", followup_message)

    async def test_followup_merges_only_selected_candidate(self):
        provider = SequenceProvider(
            [
                {
                    "type": "batch",
                    "candidates": [
                        {
                            "id": "candidate_1",
                            "kind": "calendar",
                            "calendar": {
                                "title": "Team meeting",
                                "start_time": "2026-05-06",
                                "is_all_day": False,
                            },
                        },
                        {
                            "id": "candidate_2",
                            "kind": "reminder",
                            "reminder": {
                                "title": "Submit report",
                                "due_date": "2026-05-07",
                            },
                        },
                    ],
                },
                {
                    "type": "batch",
                    "candidates": [
                        {
                            "id": "candidate_1",
                            "kind": "calendar",
                            "calendar": {
                                "title": "Team meeting",
                                "start_time": "2026-05-06T15:00:00",
                                "end_time": "2026-05-06T16:00:00",
                            },
                        },
                    ],
                },
            ]
        )
        agent = JarvisAgent()

        await agent.run("截图 OCR", session_id="s1", provider=provider)
        result = await agent.run(
            "下午三点",
            session_id="s1",
            provider=provider,
            selected_candidate_ids=["candidate_1"],
            corrections={"id": "candidate_1", "missing_fields": "time,duration"},
        )

        self.assertEqual(len(result["candidates"]), 2)
        self.assertEqual(result["candidates"][0]["calendar"]["start_time"], "2026-05-06T15:00:00")
        self.assertEqual(result["candidates"][1]["reminder"]["title"], "Submit report")
        followup_message = provider.calls[1]["messages"][0]["content"]
        self.assertIn("selected_candidate_ids", followup_message)
        self.assertIn("candidate_1", followup_message)
        self.assertIn("Team meeting", followup_message)
        self.assertNotIn("Submit report", followup_message)

    async def test_input_mode_changes_prompt_passed_to_provider(self):
        provider = MockProvider({"type": "none", "reply": "no"})

        await JarvisAgent().run("OCR text", input_mode="ocr_text", provider=provider)

        self.assertIn("输入模式：截图 OCR 文本", provider.last_call["system_prompt"])

    async def test_date_only_batch_calendar_candidate_does_not_retry(self):
        provider = MockProvider(
            {
                "type": "batch",
                "candidates": [
                    {
                        "kind": "calendar",
                        "calendar": {
                            "title": "Team meeting",
                            "start_time": "2026-05-06",
                            "is_all_day": False,
                        },
                    }
                ],
            }
        )

        result = await JarvisAgent().run("明天下午开会", provider=provider)

        candidate = result["candidates"][0]
        self.assertEqual(candidate["status"], "needs_input")
        self.assertIn("time", candidate["missing_fields"])
        self.assertEqual(candidate["clarification_question"], "几点开始？预计持续多久？")
        self.assertEqual(len(provider.calls), 1)

    async def test_retries_invalid_result_and_returns_valid_second_attempt(self):
        provider = SequenceProvider(
            [
                {"type": "calendar", "calendar": {"title": "Meeting"}},
                {
                    "type": "calendar",
                    "calendar": {
                        "title": "Meeting",
                        "start_time": "2026-05-06T10:00:00",
                        "end_time": "2026-05-06T11:00:00",
                    },
                },
            ]
        )

        result = await JarvisAgent().run("明天开会", provider=provider)

        self.assertEqual(result["type"], "calendar")
        self.assertEqual(len(provider.calls), 2)
        self.assertIn("上一次工具调用结果无效", provider.calls[1]["messages"][0]["content"])

    async def test_returns_error_after_validation_retries(self):
        provider = MockProvider({"type": "calendar", "calendar": {"title": "Meeting"}})

        result = await JarvisAgent().run("明天开会", provider=provider)

        self.assertEqual(result["type"], "error")
        self.assertEqual(result["reply"], "识别结果格式无效，请重试")
        self.assertIn("validation_failed", result["error"])
        self.assertEqual(len(provider.calls), 3)


if __name__ == "__main__":
    unittest.main()
