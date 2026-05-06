Review the current conversation and extract any project-relevant knowledge worth preserving for the team.

Then append a structured entry to `DevMemory/Collabaration.md` using this format:

```
### {YYYY-MM-DD HH:MM} | {one-line summary}
- What: {what was done or decided}
- Why: {reason or context}
- Files: {affected files, comma-separated, or "none"}
- Decision: {key architectural or technical decision, or "none"}
- Next: {follow-up tasks or open questions, or "none"}
```

Rules:
- Only include information useful to other team members in future sessions
- Skip trivial changes, pure refactors with no decisions, or anything already documented in CLAUDE.md
- Keep each field to one concise sentence
- Do not include personal preferences or session-specific debugging noise
- If nothing worth recording happened, write a single line: `### {date} | no significant changes`
