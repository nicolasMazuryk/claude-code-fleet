---
name: one-id-per-item
description: Each REVIEW_Rn / NEED_YOU_Nn ID must cover exactly one claim or question; never bundle several
metadata:
  type: feedback
---

Every review ID covers exactly one item. Three answers to rewrite means three NEED_YOU IDs, and two distinct claims mean two REVIEW IDs. Wording variants of the *same* claim in different files can share one ID.

**Why:** Nicolas resolves items one by one (`/resolve 002 NEED_YOU_N3 …`). With a bundled ID he can't accept one part and reject another. He flagged this for 002 NEED_YOU_N3 on 2026-10-06.

**How to apply:** when writing changes.md and meta.needs_input, give each separate claim or question its own ID. When splitting an existing ID, use the next free number in that package and note "split from …" in the registry.
