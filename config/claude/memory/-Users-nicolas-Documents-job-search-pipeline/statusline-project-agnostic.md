---
name: statusline-project-agnostic
description: Claude Code statusline must stay generic; never add project-specific widgets (e.g. LinkedIn budget)
metadata:
  type: feedback
---

Statusline (ccstatusline + claude-hud via ~/.claude/statusline-combined.sh) must be project-agnostic; no per-project segments.

**Why:** Nicolas rejected a job-hunt LinkedIn-budget widget on 2026-10-08: "statusline must be project agnostic".
**How to apply:** Suggest only generic widgets (model, git, context, usage limits, cost, cache, activity) when changing the statusline.
