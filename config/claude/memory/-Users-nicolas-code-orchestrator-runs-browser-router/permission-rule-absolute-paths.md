---
name: permission-rule-absolute-paths
description: Claude Code Read/Edit allow rules need //abs/path; /path is relative to the settings file
metadata:
  node_type: memory
  type: reference
  originSessionId: 4bcb2d5b-2168-432d-a8ed-3a7917bd135a
  modified: 2026-10-24T08:55:18.951Z
---

In `~/.claude/settings.json` permission rules, `Read(/Users/x/**)` is resolved relative to the settings file and does not match. Absolute paths need a double slash: `Read(//Users/nicolas/code/orchestrator-runs/**)`, or use `~/...`.

**Why:** J32 hit the same Read permission prompt twice (2026-10-24) until the rule was changed to `//Users/...`.
**How to apply:** whenever adding path rules for run dirs or repos, use `//` or `~/` and verify a fresh background session gets past the first Read. See [[orchestrator-merge-authority]].
