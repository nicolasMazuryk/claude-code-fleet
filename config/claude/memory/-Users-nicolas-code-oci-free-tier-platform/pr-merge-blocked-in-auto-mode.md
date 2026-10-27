---
name: pr-merge-blocked-in-auto-mode
description: "`gh pr merge` is allowed by a permission rule since 2026-10-25; before that the auto-mode classifier denied chat-confirmed merges"
metadata:
  node_type: memory
  type: feedback
  originSessionId: d184c649-6be9-4397-b6fd-a13bb1cb8b21
  modified: 2026-10-25T12:36:12.960Z
---

`~/.claude/settings.json` has `"Bash(gh pr merge:*)"` in `permissions.allow` (added 2026-10-25). Before it, the auto-mode classifier denied `gh pr merge` as "Merge Without Review" despite a chat confirmation (PR #7, 2026-10-24).

**Why:** the classifier honours a permission rule, not an indirect chat OK.

**How to apply:** merge only when the user asks for it (repo rule: never push to `main` without the human); then run `gh pr merge <n> -R <owner/repo> --squash --delete-branch` yourself. If a merge is ever denied again, check the rule is still in `permissions.allow` and hand over the command; never work around a denial.
