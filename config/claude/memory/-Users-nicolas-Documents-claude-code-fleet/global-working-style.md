---
name: global-working-style
description: Cross-project rules live in ~/.claude/profile/working-style.md; dependency-ordered execution and dependents-only blocking escalation live in the orchestrate skill
metadata:
  type: feedback
---

Cross-project working rules (concise outputs, final-decision docs) live in the global profile,
`~/.claude/profile/working-style.md`, imported by `~/.claude/CLAUDE.md`. The dependency-ordered execution and blocking-escalation rules
for multi-job work live in the `orchestrate` skill (`~/.claude/skills/orchestrate/SKILL.md`, "Non-negotiables").
Don't duplicate them here.
