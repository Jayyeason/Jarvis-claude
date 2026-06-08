# CodexSessionMemory.md

## Purpose
This file defines persistent project memory for Codex across different conversations in the same repository.

## Startup Routine
At the beginning of each new task, read:
- `CodexSessionMemory.md` (this file)
- `docs/PROJECT_CONTEXT.md` (business context, domain terms, boundaries)
- `docs/ARCH_DECISIONS.md` (important technical decisions and rationale)
- `docs/WORKING_RULES.md` (coding conventions, test commands, release workflow)
- `.codex/skills/jarvis-session-memory/SKILL.md` (milestone memory logging workflow)

If any file is missing, create it from the templates below before implementation.

## Collaboration Defaults
- Prefer minimal, safe changes that satisfy the request.
- Do not refactor unrelated modules unless requested.
- Keep backwards compatibility unless explicitly approved to break it.
- Run targeted tests/lint for touched areas first, then broader checks if needed.

## Code Change Policy
- For each non-trivial change, record:
  - What changed
  - Why it changed
  - Risk and rollback plan
- Update `docs/ARCH_DECISIONS.md` when architecture or key tradeoffs change.
- Update `docs/WORKING_RULES.md` when workflow/commands/conventions change.

## Commit and PR Notes
- Use clear, scoped commit messages.
- Include test evidence in PR description.
- Call out known limitations and follow-up tasks explicitly.

## Templates

### docs/PROJECT_CONTEXT.md
```md
# Project Context

## Product Goal
- [What this project is for]

## Core User Flows
- [Flow 1]
- [Flow 2]

## Domain Terms
- [Term]: [Definition]

## Non-Goals
- [What we intentionally do not solve]
```

### docs/ARCH_DECISIONS.md
```md
# Architecture Decisions

## ADR-0001 [Title]
- Date: YYYY-MM-DD
- Status: Proposed | Accepted | Superseded
- Context: [Problem background]
- Decision: [Chosen approach]
- Consequences: [Tradeoffs, risks]
- Supersedes: [Optional ADR id]
```

### docs/WORKING_RULES.md
```md
# Working Rules

## Environment
- Runtime: [Node/Python/...]
- Package manager: [npm/pnpm/pip/...]

## Commands
- Install: `[command]`
- Dev: `[command]`
- Test: `[command]`
- Lint/Format: `[command]`

## Conventions
- [Naming/style/testing conventions]

## Release Checklist
- [ ] Tests pass
- [ ] Changelog updated
- [ ] Version bumped
```

## Memory Scope Clarification
- This repository memory is **persistent across conversations** because it lives in files.
- It is **not automatic per-session memory storage**.
- To keep memory useful, update these docs whenever assumptions or decisions change.

## Session Memory Protocol
- After each completed milestone, append one structured log entry to this file.
- Use the script:
  - `python3 .codex/skills/jarvis-session-memory/scripts/log_memory.py --summary "<done>" --files "<files>" --decision "<decision|none>" --next "<next|none>"`
- Keep entries short, factual, and free of secrets.

## Session Memory Ledger
- Structured milestone logs are appended here by `jarvis-session-memory`.
### 2026-04-20 20:36:12 +0800 | milestone
- Summary: Initialized repository memory skill and logging protocol
- Files: AGENTS.md,.codex/skills/jarvis-session-memory/SKILL.md,.codex/skills/jarvis-session-memory/scripts/log_memory.py
- Decision: Use AGENTS.md as persistent cross-conversation memory ledger
- Next: Commit and push these changes
### 2026-04-20 20:37:13 +0800 | milestone
- Summary: Committed and pushed session memory skill to remote branch
- Files: AGENTS.md,.codex/skills/jarvis-session-memory/*
- Decision: Track branch feat/model-set on origin for future updates
- Next: Use this skill in future tasks to append milestone logs
### 2026-04-20 20:45:34 +0800 | milestone
- Summary: Renamed canonical memory file to CodexSessionMemory.md and kept AGENTS.md as compatibility entrypoint
- Files: CodexSessionMemory.md,AGENTS.md,.codex/skills/jarvis-session-memory/*
- Decision: Keep AGENTS.md as pointer so Codex default bootstrap still works
- Next: Continue writing milestone logs to CodexSessionMemory.md
### 2026-04-20 21:01:29 +0800 | milestone
- Summary: Updated skill default memory target
- Files: .codex/skills/jarvis-session-memory/SKILL.md,.codex/skills/jarvis-session-memory/scripts/log_memory.py,.codex/skills/jarvis-session-memory/agents/openai.yaml
- Decision: Switch default memory target to DevMemory/Collabaration.md
- Next: Use this path for all subsequent milestone logs
### 2026-04-20 21:02:56 +0800 | milestone
- Summary: Switched default memory target to repo-relative path
- Files: .codex/skills/jarvis-session-memory/scripts/log_memory.py
- Decision: Resolve default file from repository root using .git discovery
- Next: Keep using default --log-file omission
### 2026-05-06 11:26:16 +0800 | milestone
- Summary: Checked feat/model-set branch history against origin/main and separated committed branch changes from uncommitted working tree changes.
- Files: .codex/skills/jarvis-session-memory/SKILL.md,.codex/skills/jarvis-session-memory/agents/openai.yaml,.codex/skills/jarvis-session-memory/scripts/log_memory.py,AGENTS.md
- Decision: feat/model-set contains memory-skill commits; current working tree changes are separate and uncommitted.
- Next: User can merge/rebase origin/main or inspect uncommitted changes before integrating.
### 2026-05-06 13:48:45 +0800 | milestone
- Summary: Split Python JarvisAgent into agent, prompts, tools, memory, and result components with Memory V1 prompt injection
- Files: Python/agent/agent.py,Python/agent/prompts.py,Python/agent/tools.py,Python/agent/memory.py,Python/agent/result.py,Python/agent/__init__.py,Python/gateway.py,Python/providers/claude.py,Python/providers/openai_compat.py,Python/tests/test_agent_components.py
- Decision: Memory V1 reads ~/.jarvis/user_preferences.json and injects preferences into prompt; tool surface remains create_calendar_event/create_reminder/no_event
- Next: Wire future UI/settings learning to user_preferences.json when that phase starts
### 2026-05-06 14:42:56 +0800 | milestone
- Summary: Implemented nested Calendar/Reminder chat API, typed Swift recognition models, V1 EventKit writes, and MapKit-backed location alias workflow
- Files: Python/agent/tools.py,Python/agent/result.py,Python/gateway.py,Python/providers/claude.py,Python/providers/openai_compat.py,Jarvis/Models/ChatResponse.swift,Jarvis/Models/RecognitionResult.swift,Jarvis/NativeActions/EventKitTool.swift,Jarvis/NativeActions/MapKitTool.swift,Jarvis/UI/ConfirmationCard.swift,Jarvis/UI/IslandCapsuleView.swift,Jarvis/NativeActions/CaptureManager.swift
- Decision: Location remains native workflow with memory/MapKit fallback; travel_time_minutes and flagged stay in API but are not written through current macOS EventKit SDK because those members are unavailable
- Next: Consider a native bridge for Calendar travel time and Reminder flag if exact UI parity is required
### 2026-05-06 14:44:22 +0800 | milestone
- Summary: Verified nested API implementation with Python unit tests and Xcode build; aligned default reminder priority/list with V1 decisions
- Files: Python/agent/memory.py,Python/tests/test_agent_components.py,Jarvis/Models/ChatResponse.swift,Jarvis/Models/RecognitionResult.swift,Jarvis/NativeActions/EventKitTool.swift
- Decision: Reminder default priority is none and default list is 提醒事项; current macOS SDK build does not expose direct travel time or flagged writes
- Next: Manual runtime test through /chat and confirmation card with real provider
### 2026-05-06 14:51:56 +0800 | milestone
- Summary: Tightened tool schema constraints and expanded Jarvis prompt field rules for Calendar, Reminder, recurrence, and no-event safety
- Files: Python/agent/tools.py,Python/agent/prompts.py,Python/tests/test_agent_components.py
- Decision: Keep Calendar required as title/start_time, Reminder required as title, and no_event tool as forced-tool-call safety exit
- Next: Runtime-test model behavior on ambiguous screenshots and tune prompt examples if needed
### 2026-05-06 15:01:36 +0800 | milestone
- Summary: Unified runtime memory under ~/.jarvis/memory.json with generated read-only ~/.jarvis/memory.md view
- Files: Python/agent/memory.py,Python/tests/test_agent_components.py,Jarvis/NativeActions/MapKitTool.swift
- Decision: memory.json is machine source of truth; memory.md is generated human-readable read-only mirror; legacy preference/location files remain readable as fallback
- Next: Add settings UI or explicit memory migration command if manual preference editing becomes common
### 2026-05-06 15:09:19 +0800 | milestone
- Summary: Added explicit input_mode request flow and Base+mode prompt composition for vision, OCR text, and user text
- Files: Jarvis/Models/ChatRequest.swift,Jarvis/NativeActions/CaptureManager.swift,Python/gateway.py,Python/agent/agent.py,Python/agent/prompts.py,Python/tests/test_agent_components.py
- Decision: Use Swift-provided input_mode; multimodal capability remains determined by provider_configs vision_models via /config active_model_vision
- Next: Tune mode-specific prompt wording after runtime recognition tests with real OCR output
### 2026-05-06 15:14:49 +0800 | milestone
- Summary: Added persistent Swift and Python logging for capture, gateway chat, provider calls, HTTP status, decode failures, and island state transitions
- Files: Jarvis/App/Logger.swift,Jarvis/App/GatewayManager.swift,Jarvis/Gateway/GatewayClient.swift,Jarvis/NativeActions/CaptureManager.swift,Jarvis/App/JarvisApp.swift,Jarvis/UI/IslandWindowController.swift,Python/logger.py,Python/gateway.py,Python/agent/agent.py,Python/providers/claude.py,Python/providers/openai_compat.py
- Decision: Use ~/Library/Logs/Jarvis/app.log for Swift app events and ~/Library/Logs/Jarvis/python.log for Python/provider events
- Next: Reproduce the capture hang/crash and inspect app.log/python.log around the failure timestamp
### 2026-05-06 15:17:16 +0800 | milestone
- Summary: Moved Swift and Python runtime logs to repo-local /Users/kk/Jarvis-claude/.logs
- Files: Jarvis/App/Logger.swift,Python/logger.py
- Decision: Use .logs/app.log and .logs/python.log for local development diagnostics
- Next: Re-run capture and inspect .logs files if recognition hangs or app crashes
### 2026-05-06 15:20:58 +0800 | milestone
- Summary: Diagnosed OCR path decode failure from stale flat gateway response and added Swift backward-compatible ChatResponse decoding
- Files: Jarvis/Models/ChatResponse.swift
- Decision: Swift accepts both new nested type payloads and old event_type flat payloads to avoid crashes during stale gateway/app restarts
- Next: Restart app and gateway, then retest OCR text-model path with .logs tailing
### 2026-05-06 15:24:10 +0800 | milestone
- Summary: Removed legacy flat ChatResponse compatibility and killed stale Jarvis/gateway processes before strict rebuild
- Files: Jarvis/Models/ChatResponse.swift
- Decision: App now requires new type + calendar/reminder response schema only
- Next: Launch fresh app with make run and retest OCR/text-model path
### 2026-06-01 18:42:59 +0800 | milestone
- Summary: Inspected repository to summarize Jarvis purpose, architecture, implemented MVP features, and current gaps
- Files: README.md,docs/jarvis_mvp.md,docs/jarvis_dev_doc.md,Jarvis/App/JarvisApp.swift,Jarvis/NativeActions/CaptureManager.swift,Python/gateway.py
- Decision: None
- Next: None
### 2026-06-01 18:55:38 +0800 | milestone
- Summary: Implemented MVP agent stabilization: Python result validation/retry, visible no-event/error feedback, duration selection, and EventKit missing-start guard
- Files: Python/agent/validator.py,Python/agent/agent.py,Python/tests/test_agent_components.py,Jarvis/UI/IslandCapsuleView.swift,Jarvis/UI/IslandWindowController.swift,Jarvis/App/JarvisApp.swift,Jarvis/NativeActions/EventKitTool.swift
- Decision: Keep current single-turn extraction architecture; defer Keychain migration and full ReAct/Heartbeat work
- Next: Manual runtime test with a configured provider for no-event, needs-duration calendar, and normal reminder flows
### 2026-06-01 19:46:45 +0800 | milestone
- Summary: Implemented MLX local model management and model-source switching: gateway local model registry/download/load APIs, Swift model manager window/status menu entries, and Dynamic Island source switcher.
- Files: Python/gateway.py,Python/providers/local_model_registry.py,Python/providers/mlx_local.py,Python/providers/provider_factory.py,Python/requirements.txt,Python/tests/test_agent_components.py,Jarvis/Gateway/GatewayClient.swift,Jarvis/UI/APISettingsPanel.swift,Jarvis/UI/IslandCapsuleView.swift,Jarvis/UI/IslandDropdownMenu.swift,Jarvis/Commands/APISettingsWindowManager.swift,Jarvis/Commands/JarvisCommands.swift,Jarvis/UI/StatusBarController.swift,Jarvis/App/JarvisApp.swift,Jarvis/Store/APIConfigStore.swift
- Decision: Cloud API config remains in ~/.jarvis/api_config.json; local MLX models live under ~/Library/Application Support/Jarvis/Models; Dynamic Island only switches configured cloud sources or installed MLX sources.
- Next: Improve long-running download progress granularity and consider Keychain migration for API secrets.
### 2026-06-04 14:05:56 +0800 | milestone
- Summary: Added multi API-key management for cloud providers with masked key display and active key switching
- Files: Python/gateway.py,Python/tests/test_agent_components.py,Jarvis/Models/SettingsRequest.swift,Jarvis/Gateway/GatewayClient.swift,Jarvis/Store/APIConfigStore.swift,Jarvis/UI/APISettingsPanel.swift
- Decision: Keep raw keys in existing ~/.jarvis/api_config.json storage for compatibility; expose only masked key metadata through /config and switch by api_key_id
- Next: Manual runtime test adding and switching two DeepSeek keys from API settings
### 2026-06-04 14:13:13 +0800 | milestone
- Summary: Added stop script and make stop target for terminating Jarvis app, gateway.py, and port 8765 listeners
- Files: scripts/stop_jarvis.sh,Makefile
- Decision: Use graceful TERM with timed KILL fallback; JARVIS_GATEWAY_PORT and JARVIS_STOP_TIMEOUT allow overrides
- Next: Use make stop before make run when restarting local development
### 2026-06-04 14:40:11 +0800 | milestone
- Summary: Switched Jarvis from status-bar agent mode to regular macOS app mode with left-side app commands
- Files: Jarvis/App/JarvisApp.swift,Jarvis/project.yml,Jarvis/Resources/Info.plist
- Decision: Disable LSUIElement and use NSApp regular activation; do not instantiate StatusBarController so the right-side menu bar icon is removed
- Next: Restart with make stop then make run and verify Jarvis / 操作 / 模型 appears when Jarvis is active
### 2026-06-04 15:01:10 +0800 | milestone
- Summary: Added regular Jarvis main window and delayed activation so Jarvis becomes frontmost and shows left-side app menus
- Files: Jarvis/App/JarvisApp.swift,Jarvis/UI/JarvisMainView.swift
- Decision: Regular app mode needs a visible key window; launch now makes the main window key and activates Jarvis after window creation
- Next: Use make stop && make run and verify Jarvis / 操作 / 模型 in the macOS menu bar
### 2026-06-04 15:04:15 +0800 | milestone
- Summary: Made Jarvis floating island clicks activate the regular app so left-side macOS menus appear
- Files: Jarvis/UI/IslandWindowController.swift
- Decision: Keep island as nonactivating floating panel for layout, but intercept mouse-down events in sendEvent to call NSApp.activate
- Next: Manually click the island after focusing another app and verify Jarvis / 操作 / 模型 appears
### 2026-06-04 16:38:45 +0800 | milestone
- Summary: Adjusted task list popover to appear below the current island panel and added a close button
- Files: Jarvis/App/JarvisApp.swift,Jarvis/UI/IslandWindowController.swift,Jarvis/Commands/TaskListWindowManager.swift,Jarvis/UI/TaskListPanel.swift
- Decision: Anchor the schedule/reminder panel to IslandWindowController.currentPanelFrame instead of notchRect so it does not overlap the expanded island
- Next: Manual click test: open 日程/提醒 panel from island, confirm it appears below and closes via xmark
### 2026-06-04 16:49:30 +0800 | milestone
- Summary: Changed API key management UI from dropdown picker to visible masked key list with per-key switch buttons
- Files: Jarvis/UI/APISettingsPanel.swift
- Decision: Show all saved provider API keys inline; active key is marked current and inactive rows expose direct switch action
- Next: Manual API settings check with multiple DeepSeek keys
### 2026-06-06 14:35:57 +0800 | milestone
- Summary: Added generated contract pipeline and Python batch AgentResponse DTOs with Memory files and HeartbeatEngine endpoints
- Files: Python/contracts.py,scripts/generate_swift_contracts.py,Jarvis/Models/GeneratedContracts.swift,Python/gateway.py,Python/agent/tools.py,Python/agent/result.py,Python/agent/validator.py,Python/agent/prompts.py,Python/agent/agent.py,Python/agent/memory.py,Python/agent/heartbeat.py,Python/providers/mlx_local.py,Makefile,Python/requirements.txt
- Decision: Use Python Pydantic contracts as source for new chat/heartbeat/memory DTOs; preserve old API settings models for now
- Next: Wire Swift to AgentResponse, add batch review UI, conflict checks, heartbeat notifications
### 2026-06-06 14:55:42 +0800 | milestone
- Summary: Implemented unified Python-to-Swift contracts for settings/model DTOs, added agent session follow-up handling, exposed memory feedback, and wired batch review write/skip feedback.
- Files: Python/contracts.py,Python/gateway.py,Python/agent/agent.py,Python/tests/test_agent_components.py,Jarvis/Models/GeneratedContracts.swift,Jarvis/Models/ContractConvenience.swift,Jarvis/Gateway/GatewayClient.swift,Jarvis/Store/APIConfigStore.swift,Jarvis/UI/BatchReviewPanel.swift,Makefile
- Decision: Python/contracts.py is the source of truth for Swift API DTOs; Swift UI-only protocol/computed helpers live in ContractConvenience.swift.
- Next: Run make build after contract changes; consider adding a visible chat input for follow-up clarification beyond the batch editor.
### 2026-06-06 15:56:22 +0800 | milestone
- Summary: Fixed DeepSeek invalid model error by changing saved local config from gpt-4o to deepseek-v4-flash and updating DeepSeek preset models to deepseek-v4-flash/deepseek-v4-pro.
- Files: Python/providers/provider_configs.py,Python/gateway.py,Jarvis/UI/APISettingsPanel.swift,/Users/kk/.jarvis/api_config.json
- Decision: Use deepseek-v4-flash as the default DeepSeek model for fast validation; expose deepseek-v4-pro as the higher quality option.
- Next: Restart with make stop && make run, then test screenshot recognition again.
### 2026-06-06 16:56:43 +0800 | milestone
- Summary: Updated cloud API settings UI so model ID is always editable alongside API key/base URL, with preset/verified models offered as menu choices without overwriting typed IDs.
- Files: Jarvis/UI/APISettingsPanel.swift
- Decision: Model ID is now a first-class editable setting; verification preserves the typed model instead of selecting the first returned model.
- Next: Restart with make stop && make run and configure DeepSeek/OpenAI by entering API key plus model ID.
### 2026-06-06 17:06:05 +0800 | milestone
- Summary: Changed DeepSeek tool_choice compatibility to code-level error handling: OpenAI-compatible provider retries without tool_choice when required tool_choice is rejected.
- Files: Python/providers/openai_compat.py,Python/agent/prompts.py,Python/tests/test_agent_components.py
- Decision: Do not rely on prompt fallback for unsupported tool_choice; handle provider 400 errors by changing request parameters and retrying.
- Next: Restart Jarvis and retest DeepSeek screenshot recognition.
### 2026-06-06 18:09:23 +0800 | milestone
- Summary: Implemented stacked sequential batch review UI: each recognized calendar/reminder is handled as an independent card, write/skip advances automatically, and island dropdown animations were smoothed.
- Files: Jarvis/UI/BatchReviewPanel.swift,Jarvis/UI/IslandCapsuleView.swift,Jarvis/UI/IslandWindowController.swift,Jarvis/Commands/BatchReviewWindowManager.swift
- Decision: Batch review uses a confirmation-window deck, not inline island editing; write/skip auto-advances and bulk write is removed.
- Next: Manual-run Jarvis and test multi-candidate screenshot flow plus island appear/dismiss animation.
### 2026-06-06 18:21:46 +0800 | milestone
- Summary: Changed post-recognition UX: batch results now auto-open the stacked confirmation window, island only shows compact 'recognized N items' status, and confirmation window was reduced to 640x500.
- Files: Jarvis/App/JarvisApp.swift,Jarvis/UI/IslandWindowController.swift,Jarvis/UI/IslandCapsuleView.swift,Jarvis/Commands/BatchReviewWindowManager.swift,Jarvis/UI/BatchReviewPanel.swift
- Decision: Batch results no longer use the island dropdown summary; none/error results still use the island dropdown. Conflict handling remains warn-and-confirm-overwrite.
- Next: Manual test capture flow for batch, none/error, and calendar conflict cases.
### 2026-06-06 23:31:13 +0800 | milestone
- Summary: Reduced slow recognition retries: DeepSeek skips required tool_choice and date-only timed calendar candidates become needs_input instead of validation retries.
- Files: Python/providers/openai_compat.py,Python/providers/provider_configs.py,Python/providers/provider_factory.py,Python/agent/validator.py,Python/tests/test_agent_components.py
- Decision: DeepSeek should not send tool_choice=required; recoverable missing time stays in batch review as needs_input.
- Next: Restart Jarvis and test screenshot recognition with DeepSeek v4-flash/pro; consider switching active model to v4-flash for lower latency.
### 2026-06-06 23:31:36 +0800 | milestone
- Summary: Validated retry-reduction changes with Python unit tests and make build.
- Files: DevMemory/Collabaration.md,Jarvis/Models/GeneratedContracts.swift,Jarvis/Jarvis.xcodeproj/project.pbxproj,Python/providers/openai_compat.py,Python/providers/provider_configs.py,Python/providers/provider_factory.py,Python/agent/validator.py,Python/tests/test_agent_components.py
- Decision: Recognition speed bottleneck remains cloud LLM latency; current code now avoids avoidable DeepSeek/tool_choice and missing-time validation retries.
- Next: User can restart with make stop && make run and compare /chat elapsed logs; switch active DeepSeek model to deepseek-v4-flash for faster tests.
### 2026-06-07 00:03:27 +0800 | milestone
- Summary: Made recoverable missing schedule fields explicit in batch review UI: date-only calendar candidates prompt for start time/duration and cannot be written until missing fields are resolved.
- Files: Jarvis/UI/BatchReviewPanel.swift,DevMemory/Collabaration.md
- Decision: Missing date/time detail should be handled through user completion in review flow, not LLM validation retry.
- Next: Restart Jarvis and test date-only OCR text; card should show 待补充 and clear fields after selecting time/duration.
### 2026-06-07 00:27:07 +0800 | milestone
- Summary: Implemented right-docked stacked batch queue: LLM follow-up input per candidate, auto-write after completion, conflict pause with selected replacement, and EventKit deleteEvents.
- Files: Jarvis/UI/BatchReviewPanel.swift,Jarvis/Commands/BatchReviewWindowManager.swift,Jarvis/NativeActions/EventKitTool.swift,Python/agent/agent.py,Python/tests/test_agent_components.py
- Decision: Field completion uses LLM follow-up scoped to selected_candidate_ids; completed current item auto-writes unless conflicts require user action.
- Next: Restart Jarvis with make stop && make run and test screenshot recognition with multiple events, missing time, and conflict replacement.
### 2026-06-07 00:43:55 +0800 | milestone
- Summary: Added prompt examples for calendar vs reminder classification, especially date-only reminders like 明天记得交电费 requiring time follow-up; memory prompt now treats reminder due time as learned only when explicit.
- Files: Python/agent/prompts.py,Python/agent/memory.py,Python/tests/test_agent_components.py
- Decision: Date-only or fuzzy-time reminders should set missing_fields time unless stable user memory explicitly supplies a reminder habit; template defaults are not learned preferences.
- Next: Restart Python gateway/app and test screenshot/text reminder flow.
### 2026-06-07 00:56:36 +0800 | milestone
- Summary: Improved batch review card presentation and added capture/OCR/LLM timing logs
- Files: Jarvis/UI/BatchReviewPanel.swift,Jarvis/Commands/BatchReviewWindowManager.swift,Jarvis/NativeActions/CaptureManager.swift
- Decision: Keep OCR accuracy mode unchanged; add segmented timing first because observed latency is dominated by cloud LLM completion
- Next: Restart Jarvis and compare Capture OCR elapsed vs GatewayClient /chat elapsed in .logs/app.log
### 2026-06-07 01:00:53 +0800 | milestone
- Summary: Updated island model switcher to show full model IDs without truncation
- Files: Jarvis/UI/IslandCapsuleView.swift,Jarvis/UI/IslandDropdownMenu.swift
- Decision: Model switch menu titles should use raw modelId; provider/capability details move to subtitle and long text wraps
- Next: Restart Jarvis and verify long cloud/local model IDs render fully in the island model menu
### 2026-06-07 01:26:31 +0800 | milestone
- Summary: Implemented per-event isolated follow-up and dialog-style batch review confirmation
- Files: Python/contracts.py,Python/agent/agent.py,Python/agent/validator.py,Python/agent/tools.py,Python/agent/result.py,Python/agent/prompts.py,Python/providers/mlx_local.py,Python/tests/test_agent_components.py,Jarvis/Models/GeneratedContracts.swift,Jarvis/UI/BatchReviewPanel.swift
- Decision: Use LLM-provided clarification_question with validator fallback; ready events require explicit user write confirmation
- Next: Restart Jarvis and manually test multi-event screenshot with missing time/duration
### 2026-06-07 01:49:40 +0800 | milestone
- Summary: Redesigned batch review as stacked event cards and improved detail time editors
- Files: Jarvis/UI/BatchReviewPanel.swift
- Decision: Remove the visible queue header; keep sequential queue behavior with full-card stacked previews and reusable DateTimeEditRow controls
- Next: Restart Jarvis and manually verify multi-event stacked card transitions plus expanded detail date/time editing
### 2026-06-07 01:55:25 +0800 | milestone
- Summary: Removed batch follow-up input placeholder and confirmed EventKit write target behavior
- Files: Jarvis/UI/BatchReviewPanel.swift,Jarvis/NativeActions/EventKitTool.swift
- Decision: Jarvis does not write tags; calendar writes use model calendar_name or EventKit default new-event calendar, reminders use list_name default 提醒事项 then EventKit default reminders list
- Next: Consider adding explicit calendar/reminder list selector if users need to avoid system default targets like 生日
### 2026-06-07 02:05:27 +0800 | milestone
- Summary: Refined batch review card window and prompt time baseline
- Files: Python/agent/prompts.py,Python/tests/test_agent_components.py,Jarvis/Commands/BatchReviewWindowManager.swift,Jarvis/UI/BatchReviewPanel.swift
- Decision: Prompt current_time now includes local timezone offset; batch review uses a keyable borderless transparent window and hides missing_fields from the follow-up conversation UI
- Next: Restart Jarvis and manually verify compact stacked cards plus follow-up input focus
### 2026-06-07 02:12:25 +0800 | milestone
- Summary: Added always-visible event information summary to batch review cards
- Files: Jarvis/UI/BatchReviewPanel.swift
- Decision: Show read-only event details in the card body for both needs_input and ready states; keep edit details only for modifications
- Next: Restart Jarvis and manually verify ready and needs-input cards show final/known write information without opening details
### 2026-06-07 13:39:36 +0800 | milestone
- Summary: Removed the write-target calendar row from the batch review event summary and verified the build.
- Files: Jarvis/UI/BatchReviewPanel.swift
- Decision: Do not show the target Calendar field in event cards; keep event summary focused on time, location, alert and notes.
- Next: Continue optimizing recognition latency; recent logs show model /chat dominates rather than OCR.
### 2026-06-07 14:06:59 +0800 | milestone
- Summary: Implemented preference memory loop with post-processing, applied preference UI prompts, and feedback-driven learning.
- Files: Python/agent/memory.py, Python/agent/preferences.py, Python/agent/agent.py, Python/contracts.py, Python/gateway.py, Jarvis/UI/BatchReviewPanel.swift, Jarvis/Models/GeneratedContracts.swift, Jarvis/NativeActions/MapKitTool.swift
- Decision: Keep session memory in-process; persist only structured preference memory in ~/.jarvis/memory.json and apply stable preferences after LLM extraction before Swift review.
- Next: Restart Jarvis and test scenarios with learned/manual reminder time and alert preferences.
### 2026-06-07 14:21:25 +0800 | milestone
- Summary: Implemented floating-window assistant chat entry with /assistant/chat, preference command parsing, schedule handoff to batch review, and transient chat UI.
- Files: Python/agent/assistant_chat.py, Python/gateway.py, Python/contracts.py, Jarvis/UI/AssistantChatPanel.swift, Jarvis/Commands/AssistantChatWindowManager.swift, Jarvis/UI/IslandCapsuleView.swift
- Decision: Replace the island ellipsis entry with a chat icon; preference commands update memory directly, while schedule/reminder creation still opens the existing review cards before write.
- Next: Restart Jarvis and test island chat for casual chat, preference updates, and schedule/reminder creation.
### 2026-06-07 14:41:18 +0800 | milestone
- Summary: Added assistant chat action planning contracts and planner tests for list/delete/reschedule local actions.
- Files: Python/contracts.py,Python/agent/assistant_chat.py,Python/gateway.py,Python/tests/test_agent_components.py,Jarvis/Models/GeneratedContracts.swift
- Decision: LLM plans local operations via JSON chat; Swift executes EventKit actions after confirmation.
- Next: Finish Swift chat UI execution and build verification.
### 2026-06-07 14:42:30 +0800 | milestone
- Summary: Implemented assistant chat local operations: intro copy, list summaries, delete/reschedule confirmation cards, EventKit query/delete/update execution, and batch write result callbacks.
- Files: Jarvis/UI/AssistantChatPanel.swift,Jarvis/NativeActions/EventKitTool.swift,Jarvis/UI/BatchReviewPanel.swift,Jarvis/Commands/BatchReviewWindowManager.swift,Jarvis/Commands/AssistantChatWindowManager.swift,Jarvis/App/HeartbeatManager.swift
- Decision: Delete/reschedule require both date range and target keyword plus user confirmation before EventKit mutation.
- Next: Manual runtime test with chat examples after restarting Jarvis.
### 2026-06-07 14:54:07 +0800 | milestone
- Summary: Fixed Jarvis-created Calendar/Reminder containers: EventKit now creates/uses Jarvis calendar and Jarvis reminder list, independent of user preferences.
- Files: Jarvis/NativeActions/EventKitTool.swift,Jarvis/UI/BatchReviewPanel.swift,Jarvis/Models/RecognitionResult.swift,Python/agent/memory.py,Python/agent/preferences.py,Python/agent/prompts.py,Python/contracts.py,Python/agent/result.py,Python/agent/validator.py,Python/agent/tools.py,Python/tests/test_agent_components.py
- Decision: Calendar/reminder container is a fixed Jarvis group, not a preference; reminder/time preferences remain learnable.
- Next: Manual runtime test: create one event and one reminder, verify iCloud Jarvis calendar/list are created and used.
### 2026-06-07 15:22:34 +0800 | milestone
- Summary: Changed creation targets from Jarvis containers to system default calendar and Reminders list named 提醒事项; assistant chat now auto-writes one ready text candidate without confirmation.
- Files: Jarvis/NativeActions/EventKitTool.swift,Jarvis/UI/AssistantChatPanel.swift,Python/agent/prompts.py,Python/agent/result.py,Python/agent/validator.py,Python/agent/tools.py,Python/contracts.py
- Decision: Direct auto-write is limited to one ready candidate from assistant chat text; conflicts/missing info/multi-candidate flows still use review cards.
- Next: Restart Jarvis and manually test chat creation into 事项/提醒事项.
### 2026-06-07 15:28:22 +0800 | milestone
- Summary: Fixed assistant chat extraction context leak: each text creation now uses a unique agent session, and terminal feedback clears pending agent sessions.
- Files: Python/gateway.py,Jarvis/UI/AssistantChatPanel.swift,Python/tests/test_agent_components.py
- Decision: Normal assistant chat messages are independent creation requests; only review-card followups use the agent session returned by the candidate response.
- Next: Restart Jarvis and verify a completed reminder is not re-mentioned in the next chat creation.
### 2026-06-07 15:54:05 +0800 | milestone
- Summary: Fixed reminder due time handling for assistant chat auto-write: due_date plus due_time now merges for display and datetime due_date normalizes into dueTime for EventKit writes.
- Files: Jarvis/Models/RecognitionResult.swift,Jarvis/UI/AssistantChatPanel.swift,Jarvis/NativeActions/EventKitTool.swift
- Decision: Pure date reminders remain date-only; explicit due_time or datetime due_date is shown and written with hour/minute.
- Next: Restart Jarvis and test 今天晚上8点/7点提醒 writes display 20:00/19:00.
### 2026-06-07 16:03:25 +0800 | milestone
- Summary: Added assistant chat update_alert operation for existing calendar/reminder alerts; alert changes execute directly without review-card replacement.
- Files: Python/contracts.py,Python/agent/assistant_chat.py,Python/gateway.py,Jarvis/UI/AssistantChatPanel.swift,Jarvis/NativeActions/EventKitTool.swift,Jarvis/Models/GeneratedContracts.swift
- Decision: Phrases like 今晚9点的开会提前20min提醒我 are local alert updates, not new schedule extraction and not event rescheduling; target time_of_day filters matches.
- Next: Restart Jarvis and test modifying a 21:00 event to提前20分钟提醒.
### 2026-06-07 16:16:09 +0800 | milestone
- Summary: Improved assistant chat modification success summaries and list item icons.
- Files: Jarvis/UI/AssistantChatPanel.swift
- Decision: List output uses emoji icons while operation cards keep SF Symbols to avoid duplicate icons.
- Next: None
### 2026-06-07 16:22:02 +0800 | milestone
- Summary: Fixed assistant chat intent routing so new calendar/reminder requests with alert offsets are not treated as existing alert updates.
- Files: Python/agent/assistant_chat.py, Python/tests/test_agent_components.py
- Decision: Creation requests like '明天下午3点开会，持续1小时，提前30min提醒我' bypass local operation planning and enter schedule extraction; existing targets like '今晚9点的开会提前20min提醒我' remain update_alert.
- Next: Restart gateway/app before retesting chat routing.
### 2026-06-07 16:26:35 +0800 | milestone
- Summary: Enabled text selection in the assistant chat message list so conversation text can be copied.
- Files: Jarvis/UI/AssistantChatPanel.swift
- Decision: Applied SwiftUI textSelection at the message list level so bubbles, list output, and operation card text inherit selectable text.
- Next: Restart app/gateway and verify selecting chat text with mouse drag and Cmd+C.
### 2026-06-07 16:36:24 +0800 | milestone
- Summary: Fixed assistant chat local-operation routing for implicit list queries and clarification follow-ups.
- Files: Python/agent/assistant_chat.py, Python/gateway.py, Python/tests/test_agent_components.py
- Decision: Implicit queries like '最近2天的日程和待办' and clarification answers like '未来2天' now route to list_items with deterministic fallback instead of ordinary chat.
- Next: Restart gateway/app before retesting assistant chat list queries.
### 2026-06-07 16:40:22 +0800 | milestone
- Summary: Fixed slash-separated calendar/reminder list query keyword cleanup.
- Files: Python/agent/assistant_chat.py, Python/tests/test_agent_components.py
- Decision: Queries like '查看未来2天的日程/提醒事项' route to list_items with item_kind=both, future 2-day date range, and no title keyword filter.
- Next: Restart gateway/app before retesting this exact phrase.
### 2026-06-07 16:44:30 +0800 | milestone
- Summary: Added stable /list assistant chat command for local calendar/reminder list queries.
- Files: Python/agent/assistant_chat.py, Python/tests/test_agent_components.py
- Decision: /list queries route to list_items, default to calendar+reminders when no kind is specified, and strip command/separator words from title keywords.
- Next: Restart gateway/app before retesting /list queries.
### 2026-06-07 16:49:16 +0800 | milestone
- Summary: Changed assistant list queries to always include both calendar events and reminders.
- Files: Python/agent/assistant_chat.py, Python/tests/test_agent_components.py
- Decision: For action=list_items, item_kind is forced to both even if the user says only 日程 or only 待办/提醒事项; Chinese day counts like 两天 are parsed deterministically.
- Next: Restart gateway/app before retesting list queries.
### 2026-06-07 17:25:20 +0800 | milestone
- Summary: Implemented grouped assistant list output with alert reminder summaries and Markdown rendering.
- Files: Python/contracts.py, Jarvis/Models/GeneratedContracts.swift, Jarvis/NativeActions/EventKitTool.swift, Jarvis/App/HeartbeatManager.swift, Jarvis/UI/AssistantChatPanel.swift
- Decision: List output groups items into 今天/明天/一周内/更晚/未定时间, includes alert labels, and assistant messages render Markdown while retaining selectable text.
- Next: Restart gateway/app and verify /list output with calendar events and reminders.
### 2026-06-07 17:44:01 +0800 | milestone
- Summary: Fixed assistant chat list rendering and local operation routing for schedule creation/reschedule/update-alert cases.
- Files: Jarvis/UI/AssistantChatPanel.swift,Jarvis/NativeActions/EventKitTool.swift,Python/agent/assistant_chat.py,Python/contracts.py,Jarvis/Models/GeneratedContracts.swift,Python/tests/test_agent_components.py
- Decision: New schedule requests bypass local update routing; list output is grouped by time buckets with one item per line; target time_period is part of the Swift/Python contract.
- Next: Restart Jarvis and test assistant chat with /list, new schedule creation, and reschedule/update-alert phrases.
### 2026-06-07 17:57:37 +0800 | milestone
- Summary: Fixed assistant chat route so explicit add/new schedule requests with alert text create candidates instead of updating existing alerts.
- Files: Python/agent/assistant_chat.py,Python/tests/test_agent_components.py
- Decision: Explicit create verbs such as 添加/新建/创建/写入/安排 take precedence over existing update_alert detection.
- Next: Restart Jarvis gateway/app and retest adding a schedule from assistant chat.
### 2026-06-07 18:06:35 +0800 | milestone
- Summary: Adjusted assistant chat routing so only slash-list uses deterministic local planning; create/update/delete/preference requests now go through LLM extraction or planner before Swift executes local tools.
- Files: Python/gateway.py,Python/agent/assistant_chat.py,Python/tests/test_agent_components.py
- Decision: Use is_schedule_creation_request for extraction; is_schedule_request remains broad and is no longer the gateway creation route. Non-/list operation heuristics are routing hints only, not planner fallbacks.
- Next: Restart gateway/app and test /list, natural list, create schedule, update alert, and preference update from assistant chat.
### 2026-06-07 18:12:34 +0800 | milestone
- Summary: Improved assistant chat creation flow: complete single ready candidates auto-write without extra confirmation, and contextual replies like 确认添加 reuse prior creation context for extraction instead of falling into normal chat.
- Files: Python/gateway.py,Python/agent/assistant_chat.py,Python/tests/test_agent_components.py
- Decision: Keep conflict/missing-info review cards, but complete no-conflict single candidate writes directly via existing Swift auto-write path.
- Next: Restart Jarvis and retest direct schedule creation plus confirmation-add follow-up.
### 2026-06-07 18:17:19 +0800 | milestone
- Summary: Changed assistant chat candidate handling so missing-info follow-up stays inside the chat window; BatchReview/right-side cards are no longer opened from AssistantChatPanel and remain for screenshot recognition flows.
- Files: Jarvis/UI/AssistantChatPanel.swift,Python/tests/test_agent_components.py
- Decision: Chat-created candidates use the existing /chat follow-up session with selected_candidate_ids; complete single candidates auto-write, missing info asks in chat, conflict/multiple candidates are reported in chat.
- Next: Restart Jarvis and test chat creation with missing time/duration plus screenshot recognition to confirm right-side cards still appear only for screenshots.
### 2026-06-07 18:21:24 +0800 | milestone
- Summary: Applied system calendar defaults during preference post-processing: missing event duration defaults to 60 minutes and missing calendar alert defaults to 10 minutes, while explicit user values and learned/manual memory preferences override defaults.
- Files: Python/agent/preferences.py,Python/agent/prompts.py,Python/tests/test_agent_components.py
- Decision: Calendar defaults are always effective; reminder due_time/alert still require stable explicit/learned preferences to avoid inventing date-only reminder times.
- Next: Restart Jarvis and test creating a calendar event with no duration/alert, with explicit duration/alert, and after learned preference promotion.
### 2026-06-07 18:54:37 +0800 | milestone
- Summary: Implemented menu-bar Memory editor for soul/user/heartbeat plus read-only wal with Gateway file APIs
- Files: Python/agent/memory.py,Python/contracts.py,Python/gateway.py,Python/tests/test_agent_components.py,Jarvis/Commands/JarvisCommands.swift,Jarvis/Commands/MemoryWindowManager.swift,Jarvis/UI/MemoryPanel.swift,Jarvis/Gateway/GatewayClient.swift,Jarvis/Models/GeneratedContracts.swift
- Decision: Expose only whitelisted memory files; user.md markdown affects prompt but is not parsed into structured preferences
- Next: Manual runtime test via 记忆 > 管理 Memory after restarting Jarvis
### 2026-06-07 22:47:30 +0800 | milestone
- Summary: Synced chat preference updates into user.md and added Markdown preview/edit mode to Memory panel
- Files: Python/agent/memory.py,Python/agent/assistant_chat.py,Python/gateway.py,Python/tests/test_agent_components.py,Jarvis/UI/MemoryPanel.swift
- Decision: Structured preferences remain source of truth; user.md preference section is generated for visibility and prompt context; Memory panel defaults to Markdown preview
- Next: Manual runtime test Assistant Chat preference update then reload user.md in Memory window
### 2026-06-07 22:51:54 +0800 | milestone
- Summary: Fixed Memory panel Markdown preview block rendering and expanded sidebar row hit areas
- Files: Jarvis/UI/MemoryPanel.swift
- Decision: Render Markdown blocks manually for headings/lists/paragraphs instead of a single inline AttributedString; keep wal.jsonl raw
- Next: Manual runtime check Memory window selection and preview rendering
### 2026-06-07 23:44:03 +0800 | milestone
- Summary: Implemented memory preference title migration, chat-updatable default reminder preferences, /cron command routing, heartbeat cron task storage, and island-only cron reminders.
- Files: Python/agent/memory.py,Python/agent/assistant_chat.py,Python/agent/cron_memory.py,Python/agent/heartbeat.py,Python/gateway.py,Jarvis/App/HeartbeatManager.swift,Python/tests/test_agent_components.py
- Decision: /cron natural-language creation uses the active LLM; /cron-list, /cron-help, and /cron-delete are deterministic; cron reminders emit trigger_type=cron_reminder and skip macOS notifications.
- Next: None
### 2026-06-07 23:51:32 +0800 | milestone
- Summary: Fixed cron creation failure when croniter is missing by adding fallback 5-field cron validation/previous-time calculation; made deterministic preference parsing override incomplete LLM update_preference plans.
- Files: Python/agent/cron_memory.py,Python/agent/heartbeat.py,Python/agent/assistant_chat.py,Python/tests/test_agent_components.py
- Decision: Cron still prefers croniter when installed but no longer fails for standard expressions like 49 23 * * * if croniter is unavailable; explicit parsed default reminder preferences override model-provided partial preference_values.
- Next: None
### 2026-06-08 00:16:20 +0800 | milestone
- Summary: Implemented controlled LLM-driven memory actions for assistant chat: update_memory planner action, AssistantMemoryAction contracts, user profile/long-term memory helpers, and gateway execution.
- Files: Python/contracts.py,Python/agent/assistant_chat.py,Python/agent/memory.py,Python/gateway.py,Python/tests/test_agent_components.py,Jarvis/Models/GeneratedContracts.swift
- Decision: Use internal controlled memory tools instead of provider-level function calling for v1; low-risk user.md updates auto-write, soul.md changes return confirmation proposals without file mutation.
- Next: None
### 2026-06-08 00:24:26 +0800 | milestone
- Summary: Improved cron assistant replies with Markdown formatting, human-readable cron descriptions, and Swift chat Markdown rendering.
- Files: Python/agent/cron_memory.py,Python/gateway.py,Jarvis/UI/AssistantChatPanel.swift,Python/tests/test_agent_components.py
- Decision: Cron replies show user-facing schedule text plus raw cron/id as secondary inline-code metadata; assistant chat renders Markdown via AttributedString.
- Next: None
### 2026-06-08 00:36:45 +0800 | milestone
- Summary: Added assistant planner fallback to plain chat and tightened memory-update routing for recall questions.
- Files: Python/agent/assistant_chat.py,Python/gateway.py,Python/tests/test_agent_components.py
- Decision: Planner parse/runtime failures in assistant chat should degrade to normal chat; recall-style questions like '我叫什么' and '我在哪里' must not trigger memory update planning.
- Next: Move toward a unified chat agent with schedule/reminder operations exposed as controlled tools instead of broad keyword pre-routing.
### 2026-06-08 00:44:25 +0800 | milestone
- Summary: Added cancellable assistant chat sends: the send button becomes a stop button while a response is in flight, cancellation restores the prompt for editing and suppresses cancellation errors.
- Files: Jarvis/UI/AssistantChatPanel.swift
- Decision: Assistant chat should keep the input editable during in-flight requests and cancel the Swift task before allowing resend; local follow-up operations check Task cancellation before appending or writing.
- Next: Consider server-side cancellation tokens if backend responses continue after client disconnects.
### 2026-06-08 00:56:53 +0800 | milestone
- Summary: Fixed assistant creation and memory profile routing: explicit timed meetings route to schedule extraction, simple profile statements like '我在上海' force controlled set_user_profile, and legacy user.md '## 城市' is migrated into '## 用户资料' then removed.
- Files: Python/agent/assistant_chat.py,Python/agent/memory.py,Python/gateway.py,Python/tests/test_agent_components.py
- Decision: New calendar/reminder creation should not ask for confirmation when fields are ready; user.md should not keep a standalone city section; Memory replies must only say written when a valid tool write happened.
- Next: Restart the Python gateway/Jarvis app to load the routing and memory migration changes.
### 2026-06-08 01:25:14 +0800 | milestone
- Summary: Fixed reminder alert handling and renamed reminder preference labels: Reminders now use absolute EKAlarm dates based on due time, reminder alert reads support legacy relative alarms, and user.md labels are migrated to '提醒事项默认当天DDL' / '提醒事项默认提前提醒时间'.
- Files: Jarvis/NativeActions/EventKitTool.swift,Jarvis/App/HeartbeatManager.swift,Python/agent/memory.py,Python/agent/assistant_chat.py,Python/tests/test_agent_components.py
- Decision: Reminder alarms should be stored as absolute dates because list/query code compares alarm.absoluteDate against dueDate; old relative alarms are treated as fallback for display.
- Next: Restart Jarvis/Python gateway; existing reminders without any persisted alarm may need their alert set once.
### 2026-06-08 01:34:37 +0800 | milestone
- Summary: Fixed cron reminder reliability by checking missed schedules between heartbeat ticks and sending cron events through system notifications.
- Files: Python/agent/heartbeat.py,Jarvis/App/HeartbeatManager.swift,Python/tests/test_agent_components.py
- Decision: Cron reminders catch up only within an active heartbeat interval, capped at 10 minutes; first startup still uses a short 65-second window to avoid stale popups.
- Next: Restart Jarvis/Python gateway and verify a near-future /cron popup manually.
### 2026-06-08 01:39:31 +0800 | milestone
- Summary: Fixed heartbeat datetime parsing so UTC ISO timestamps from Swift are converted to local time before cron and fixed-hour rules are evaluated.
- Files: Python/agent/heartbeat.py,Python/tests/test_agent_components.py,Python/agent/cron_memory.py,Python/agent/assistant_chat.py
- Decision: Heartbeat rules should evaluate wall-clock schedules in the gateway machine's local timezone; cron help/prompt now describes island plus system notifications without creating Calendar/Reminder items.
- Next: Restart Jarvis/Python gateway and verify a near-future /cron reminder fires at local wall-clock time.
### 2026-06-08 01:44:47 +0800 | milestone
- Summary: Fixed reminder explicit alert normalization so phrases like '17点提交，提前十分钟提醒' preserve due_time=17:00 and write alert_minutes_before_due=10 even if model output shifted the due time.
- Files: Python/agent/preferences.py,Python/tests/test_agent_components.py,Python/agent/prompts.py,Python/agent/tools.py
- Decision: Reminder due_time is the due/DDL time; early notification belongs only in alert_minutes_before_due. The preference post-processor now corrects shifted due times using the original user text.
- Next: Restart Python gateway/Jarvis and retest creating a reminder with an explicit early alert.
### 2026-06-08 02:00:37 +0800 | milestone
- Summary: Implemented cron system-notification-only delivery and switched future Reminders early alerts to EKAlarm relativeOffset.
- Files: Jarvis/App/HeartbeatManager.swift,Jarvis/NativeActions/EventKitTool.swift,Python/gateway.py,Python/agent/cron_memory.py,Python/agent/assistant_chat.py,Python/tests/test_agent_components.py
- Decision: Cron reminders no longer show the Jarvis island; future reminder alerts use relativeOffset while existing absolute alarms remain readable but are not migrated.
- Next: Restart Jarvis/Python gateway, create a near-future /cron and a 15:00 reminder to manually verify system notification and relative Reminders alert.
### 2026-06-08 02:10:22 +0800 | milestone
- Summary: Diagnosed cron reminder delivery: heartbeat/WAL showed cron fired, but NotificationTool failed with UNErrorDomain error 1. Added authorization-state checks, foreground notification presentation delegate, and Boolean send results.
- Files: Jarvis/NativeActions/NotificationTool.swift,Jarvis/App/HeartbeatManager.swift
- Decision: Cron remains system-notification-only; notification failures now log explicit authorization state, and foreground notifications present as banner/list/sound.
- Next: Restart Jarvis and enable Jarvis notifications in macOS Settings if logs report authorization denied.
### 2026-06-08 02:34:10 +0800 | milestone
- Summary: Fixed assistant reminder creation routing and default alert due-time preservation
- Files: Python/agent/assistant_chat.py, Python/agent/preferences.py, Python/contracts.py, Python/agent/prompts.py, Python/tests/test_agent_components.py, Jarvis/UI/BatchReviewPanel.swift
- Decision: Reminder due_time remains the user requested/default due time; early alert is stored in alert_minutes_before_due, including memory defaults
- Next: Restart Jarvis/Python gateway after pulling to use the corrected route and rebuilt app
### 2026-06-08 02:41:05 +0800 | milestone
- Summary: Fixed macOS notification registration by signing Debug app bundle and requesting notification authorization after app activation
- Files: Makefile, Jarvis/App/JarvisApp.swift, Jarvis/NativeActions/NotificationTool.swift
- Decision: Debug builds must keep a stable signed bundle identifier com.jarvis.app; Jarvis proactively prepares notification authorization on launch instead of waiting for a cron event
- Next: Use make run or restart Jarvis after pulling; re-enable Notifications and Accessibility permissions for the newly signed Jarvis if macOS prompts
### 2026-06-08 02:53:28 +0800 | milestone
- Summary: Generated A组 Jarvis project defense PPTX with 11 editable 16:9 slides and right-side blank screenshot placeholders.
- Files: docs/Jarvis_A组项目展示.pptx,DevMemory/Collabaration.md
- Decision: Used temporary /tmp python-pptx venv; kept project dependencies unchanged; placeholders use light gray straight borders.
- Next: Open in PowerPoint or Keynote to add screenshots/recordings into the reserved right-side areas.
### 2026-06-08 09:48:22 +0800 | milestone
- Summary: Updated Jarvis A组 PPTX: slides 2/3/9/10 no longer reserve right-side blank placeholders; business slide now covers current AI workplace/agent market and Jarvis value.
- Files: docs/Jarvis_A组项目展示.pptx,DevMemory/Collabaration.md
- Decision: Kept screenshot placeholders only on demo-oriented slides; added concise market-source footnote on the business analysis slide.
- Next: Open slide 9 in PowerPoint/Keynote for final visual polish if presenter wants denser or lighter market wording.
### 2026-06-08 09:53:18 +0800 | milestone
- Summary: Finalized PPTX update after user feedback: removed right-side placeholders from slides 2/3/9/10 and refined slide 9 market pain bullet with Microsoft Work Trend Index context.
- Files: docs/Jarvis_A组项目展示.pptx,DevMemory/Collabaration.md
- Decision: Business analysis slide now pairs Gallup AI adoption, Gartner agentization, Microsoft fragmented-work context, and Jarvis commercial value.
- Next: Presenter can add screenshots only to demo slides 4-8; slides 2/3/9/10 are now full-content pages.
### 2026-06-08 10:30:21 +0800 | milestone
- Summary: Implemented assistant-chat-only macOS Notes creation: note intent planning, execute_note response, Swift NotesTool AppleScript writer, UI execution, permissions, contracts, and tests.
- Files: Python/contracts.py,Python/agent/assistant_chat.py,Python/gateway.py,Python/tests/test_agent_components.py,Jarvis/Models/GeneratedContracts.swift,Jarvis/NativeActions/NotesTool.swift,Jarvis/UI/AssistantChatPanel.swift,Jarvis/project.yml,Jarvis/Resources/Info.plist,Jarvis/Jarvis.xcodeproj/project.pbxproj
- Decision: Notes creation is limited to assistant chat, creates a new single macOS note directly after explicit record/save intent, and does not alter screenshot extract_schedule_items tools.
- Next: Runtime-test with a real provider and allow Notes automation permission on first write.
### 2026-06-08 10:35:53 +0800 | milestone
- Summary: Fixed startup permission prompts and screenshot hotkey reliability: replaced Accessibility-based NSEvent global monitor with Carbon RegisterEventHotKey for Cmd+Shift+J, removed startup notification authorization, and made heartbeat skip Calendar/Reminder snapshots unless already authorized.
- Files: Jarvis/App/JarvisApp.swift,Jarvis/App/HeartbeatManager.swift,Jarvis/project.yml,Jarvis/Jarvis.xcodeproj/project.pbxproj,DevMemory/Collabaration.md
- Decision: Global screenshot hotkey no longer requires Accessibility permission; startup should not proactively prompt for Notification, Calendar, or Reminder permissions.
- Next: Runtime-test launch for no startup permission prompts, then press Cmd+Shift+J from foreground/background apps to verify capture opens.
### 2026-06-08 10:44:53 +0800 | milestone
- Summary: Hardened macOS Notes writing after AppleEvent timeout: NotesTool now uses osascript subprocess, activates Notes, wraps commands in explicit timeout, creates note body-only in default folder, returns a simple ok string, and maps timeout errors to actionable text.
- Files: Jarvis/NativeActions/NotesTool.swift,DevMemory/Collabaration.md
- Decision: Avoid NSAppleScript background-thread execution and avoid returning Notes object specifiers because both can contribute to AppleEvent timeout behavior.
- Next: Restart Jarvis and retry assistant chat note creation; if macOS prompts Automation permission, allow Jarvis/osascript to control Notes.
### 2026-06-08 10:56:02 +0800 | milestone
- Summary: Fixed assistant-chat Notes intent routing for phone-number notes and two-turn 'write to Notes' commands; added deterministic fallback note plans.
- Files: Python/agent/assistant_chat.py,Python/gateway.py,Python/tests/test_agent_components.py
- Decision: Explicit macOS Notes requests take precedence over schedule parsing; target-only Notes commands reuse the previous user message as note content.
- Next: If Notes still times out, inspect macOS Automation permission and Notes app state.
### 2026-06-08 11:01:21 +0800 | milestone
- Summary: Added direct assistant-chat Notes routing for inline commands such as '记录：18154100916 kk', including no-provider execution and no confirmation.
- Files: Python/agent/assistant_chat.py,Python/gateway.py,Python/tests/test_agent_components.py
- Decision: Colon-style record/save/memo commands are treated as macOS Notes writes in assistant chat and bypass the model; broader note requests still use planner when available.
- Next: If UI shows AppleEvent timeout, debug NotesTool/macOS Automation instead of intent routing.
### 2026-06-08 11:22:08 +0800 | milestone
- Summary: Fixed macOS Notes Automation permission flow by preflighting AEDeterminePermissionToAutomateTarget, launching Notes if needed, opening Automation settings on denial, and executing AppleScript inside Jarvis instead of /usr/bin/osascript.
- Files: Jarvis/NativeActions/NotesTool.swift
- Decision: Notes writes must originate from Jarvis process so the Automation grant for Jarvis controls the actual AppleEvent sender.
- Next: Ask user to retry note write; if denied state persists, reset AppleEvents TCC for com.jarvis.app or enable Jarvis -> Notes in Automation settings.
### 2026-06-08 11:42:26 +0800 | milestone
- Summary: Changed assistant-chat creation policy to auto-write complete single Calendar/Reminders/Notes items without confirmation; updated runtime soul.md, prompts, planner wording, and default calendar duration filling.
- Files: Python/agent/memory.py,Python/agent/prompts.py,Python/agent/preferences.py,Python/agent/assistant_chat.py,Python/tests/test_agent_components.py,/Users/kk/.jarvis/soul.md
- Decision: Only missing fields, delete/bulk modifications, conflict writes, and soul boundary changes require confirmation; complete dialogue-created items should be written by Swift automatically.
- Next: User can test with a complete calendar event, a reminder with exact time, and a note; inspect logs if model still asks confirmation.
### 2026-06-08 12:03:29 +0800 | milestone
- Summary: Added deterministic relative-date correction for schedule extraction so today/tomorrow/day-after-tomorrow dates are anchored to the local current date even when the model returns stale dates.
- Files: Python/agent/date_correction.py,Python/agent/agent.py,Python/tests/test_agent_components.py
- Decision: Relative day words in user text override model-provided date portions while preserving extracted time, duration, title, and location.
- Next: If more stale-date cases appear, extend correction to additional relative date expressions.
### 2026-06-08 12:14:50 +0800 | milestone
- Summary: Diagnosed Calendar write failures; added strict EventKit auth checks, post-save event verification, calendar logging, and stable Apple Development signing for Jarvis Debug builds.
- Files: Jarvis/NativeActions/EventKitTool.swift,Jarvis/UI/AssistantChatPanel.swift,Jarvis/App/HeartbeatManager.swift,Jarvis/project.yml,Makefile
- Decision: Ad-hoc cdhash-only signing caused TCC to treat rebuilt Debug apps as new identities; use Apple Development team K53J9V75NJ so Calendar/Reminders authorization persists after one reauthorization.
- Next: User should allow Calendar/Reminders once on the next write attempt; if creation still fails, inspect .logs/app.log EventKit lines.

