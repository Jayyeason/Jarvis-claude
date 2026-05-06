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

