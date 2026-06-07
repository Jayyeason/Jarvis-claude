import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from agent import JarvisAgent
from agent.memory import MemoryManager, UserPreferences
from agent.prompts import build_system_prompt, normalize_input_mode
from agent.result import normalize_tool_result
from agent.tools import get_anthropic_tools, get_openai_tools
from agent.validator import AgentValidationError, validate_agent_result
from providers.openai_compat import OpenAICompatProvider
from providers.local_model_registry import LocalModelRegistry, safe_model_id
from providers.provider_factory import create_provider
from gateway import (
    _active_api_key,
    _mask_secret,
    _normalize_api_keys,
    _set_active_api_key,
    _upsert_api_key,
)


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
                                "start_time": "2026-05-06T10:00:00",
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
        agent = JarvisAgent()

        first = await agent.run("明天开会", session_id="s1", provider=provider)
        second = await agent.run("时长一小时", session_id="s1", provider=provider)

        self.assertEqual(first["candidates"][0]["status"], "needs_input")
        self.assertEqual(second["candidates"][0]["calendar"]["end_time"], "2026-05-06T11:00:00")
        followup_message = provider.calls[1]["messages"][0]["content"]
        self.assertIn("单个日程/待办 event", followup_message)
        self.assertIn("current_events", followup_message)
        self.assertIn("Team meeting", followup_message)
        self.assertIn("时长一小时", followup_message)

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
