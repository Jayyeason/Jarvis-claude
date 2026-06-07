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

