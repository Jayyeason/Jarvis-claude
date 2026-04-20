# AGENTS.md

## Purpose
This file defines persistent project memory for Codex across different conversations in the same repository.

## Startup Routine
At the beginning of each new task, read:
- `AGENTS.md` (this file)
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

