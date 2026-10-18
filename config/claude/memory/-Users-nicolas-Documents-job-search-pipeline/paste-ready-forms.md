---
name: paste-ready-forms
description: application_form.md answers must be exact copy-paste text (plain-text ```text blocks), never pointers to cv.md etc.
metadata:
  type: feedback
---

Every form answer except file uploads and the cover-letter field must be the final paste text: literal value in the table cell, or a ```text block (plain text, no markdown/IDs/tags) under `### <field>`. Notes and REVIEW/NEED_YOU tags go on a `Note:` line above the block.

**Why:** Nicolas (2026-10-07) had to pull the Summary from cv.md and strip markdown by hand — extra work.
**How to apply:** rule lives in next-job.md §5.8 "Paste-ready"; qa_gate.py enforces it. Same for photo-URL fields ([[pipe-separator]] style rules still apply).
