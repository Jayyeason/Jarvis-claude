---
name: jarvis-session-memory
description: Persist project memory for the Jarvis-claude repository by appending structured milestone logs to /Users/kk/Jarvis-claude/DevMemory/Collabaration.md. Use when a subtask or milestone is completed, when key decisions are made, and before final delivery so future conversations inherit current context.
---

# Jarvis Session Memory

## Overview

Append compact, structured progress memory entries to `DevMemory/Collabaration.md` so work context survives across different conversations. Keep entries factual and scoped to completed work.

## Workflow

1. Confirm target file is `/Users/kk/Jarvis-claude/DevMemory/Collabaration.md`.
2. After each completed milestone, run:
```bash
python3 .codex/skills/jarvis-session-memory/scripts/log_memory.py \
  --summary "<what was completed>" \
  --files "<comma-separated files>" \
  --decision "<important decision or none>" \
  --next "<next action or none>"
```
3. Keep each field concise and objective.
4. Run once more at task end to capture final completion state.

## Entry Rules

- Use one log entry per completed milestone.
- Prefer concrete file paths and actions over generic wording.
- Include a decision note only when it affects future implementation.
- Do not store secrets, tokens, credentials, or private user data.

## Output Format

Append entries under the `## Session Memory Ledger` section in `DevMemory/Collabaration.md`:

```md
### YYYY-MM-DD HH:MM:SS +ZZZZ | milestone
- Summary: ...
- Files: ...
- Decision: ...
- Next: ...
```

Use `scripts/log_memory.py` for deterministic appends.
