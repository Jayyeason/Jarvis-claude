import json
import tempfile
import unittest
from pathlib import Path

from agent import JarvisAgent
from agent.memory import MemoryManager, UserPreferences
from agent.prompts import build_system_prompt, normalize_input_mode
from agent.result import normalize_tool_result
from agent.tools import get_anthropic_tools, get_openai_tools


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
                            "reminder_default_due_time": "18:30",
                            "reminder_default_priority_for_deadline": "high",
                            "calendar_default_name": "Work",
                            "reminder_default_list_name": "Tasks",
                        }
                    }
                ),
                encoding="utf-8",
            )

            prefs = MemoryManager(path).load_preferences()

        self.assertEqual(prefs.calendar_default_duration_minutes, 45)
        self.assertEqual(prefs.calendar_default_alert_minutes, 15)
        self.assertEqual(prefs.reminder_default_due_time, "18:30")
        self.assertEqual(prefs.reminder_default_priority_for_deadline, "high")
        self.assertEqual(prefs.calendar_default_name, "Work")
        self.assertEqual(prefs.reminder_default_list_name, "Tasks")

    def test_loads_legacy_flat_preference_shape_for_custom_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "legacy_preferences.json"
            path.write_text(
                json.dumps({"calendar_default_alert_minutes": 20}),
                encoding="utf-8",
            )

            prefs = MemoryManager(path).load_preferences()

        self.assertEqual(prefs.calendar_default_alert_minutes, 20)


class ToolSchemaTests(unittest.TestCase):
    def test_tool_lists_only_include_current_three_tools(self):
        anthropic_tools = get_anthropic_tools()
        openai_tools = get_openai_tools()

        self.assertEqual(
            [tool["name"] for tool in anthropic_tools],
            ["create_calendar_event", "create_reminder", "no_event"],
        )
        self.assertEqual(
            [tool["function"]["name"] for tool in openai_tools],
            ["create_calendar_event", "create_reminder", "no_event"],
        )

    def test_schema_constraints_document_defaults(self):
        tools = {tool["name"]: tool for tool in get_anthropic_tools()}
        reminder_props = tools["create_reminder"]["input_schema"]["properties"]
        calendar_props = tools["create_calendar_event"]["input_schema"]["properties"]

        self.assertEqual(reminder_props["priority"]["enum"], ["none", "low", "medium", "high"])
        self.assertEqual(reminder_props["alert_minutes_before_due"]["minimum"], 0)
        self.assertEqual(calendar_props["alert_minutes_before_start"]["minimum"], 0)
        self.assertEqual(calendar_props["recurrence"]["properties"]["interval"]["minimum"], 1)


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

        self.assertEqual(result["type"], "calendar")
        self.assertEqual(result["calendar"]["title"], "Meeting")
        self.assertFalse(result["calendar"]["needs_duration"])
        self.assertEqual(result["calendar"]["location"], "Office")
        self.assertEqual(result["calendar"]["alert_minutes_before_start"], 10)
        self.assertIsNone(result["reminder"])

    def test_reminder_result_matches_chat_response_fields(self):
        result = normalize_tool_result(
            "create_reminder",
            {"title": "Submit", "due_date": "2026-05-07", "due_time": "09:00"},
        )

        self.assertEqual(result["type"], "reminder")
        self.assertEqual(result["reminder"]["title"], "Submit")
        self.assertEqual(result["reminder"]["priority"], "none")
        self.assertEqual(result["reminder"]["list_name"], "提醒事项")
        self.assertFalse(result["reminder"]["flagged"])
        self.assertIsNone(result["calendar"])

    def test_no_event_result_matches_chat_response_fields(self):
        result = normalize_tool_result("no_event", {"reply": "没有事件"})

        self.assertEqual(result["type"], "none")
        self.assertEqual(result["reply"], "没有事件")


class MockProvider:
    def __init__(self, result):
        self.result = result
        self.last_call = None

    async def chat_with_tools(self, **kwargs):
        self.last_call = kwargs
        return self.result


class AgentRunTests(unittest.IsolatedAsyncioTestCase):
    async def test_no_provider_result_is_unchanged(self):
        result = await JarvisAgent().run("hello")

        self.assertEqual(result["type"], "error")
        self.assertEqual(result["error"], "no_provider")
        self.assertEqual(result["reply"], "请先配置 API")

    async def test_provider_result_passes_through_with_split_components(self):
        provider = MockProvider(
            {
                "type": "reminder",
                "reminder": {
                    "title": "Submit paper",
                    "due_date": "2026-05-07",
                    "priority": "high",
                },
            }
        )

        result = await JarvisAgent().run("交论文", provider=provider)

        self.assertEqual(result["type"], "reminder")
        self.assertEqual(result["reminder"]["title"], "Submit paper")
        self.assertIn("用户偏好", provider.last_call["system_prompt"])
        self.assertEqual(len(provider.last_call["tools"]), 3)
        self.assertEqual(len(provider.last_call["tools_openai"]), 3)

    async def test_input_mode_changes_prompt_passed_to_provider(self):
        provider = MockProvider({"type": "none", "reply": "no"})

        await JarvisAgent().run("OCR text", input_mode="ocr_text", provider=provider)

        self.assertIn("输入模式：截图 OCR 文本", provider.last_call["system_prompt"])


if __name__ == "__main__":
    unittest.main()
