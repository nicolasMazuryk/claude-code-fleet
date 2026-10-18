---
name: pipe-separator
description: Use " | " (not " · ") as the inline separator in all pipeline text, registries, forms, reports
metadata:
  type: feedback
---

Use ` | ` as the inline list/field separator everywhere in pipeline output (REVIEW registry lines, application_form, screening keyword lines, reports, index totals, /resolve input). Never ` · `.

**Why:** Nicolas asked on 2026-10-06 to replace · with | for current and future items.

**How to apply:** Templates in `.claude/commands/*.md` and `scripts/state.py` already use `|`. Exceptions: text inside double quotes that quotes a JD or CV verbatim keeps its original characters. CV/letter PDFs (`render.py` contact line, `cv.md` headline/languages) and `tracks/*/master.md` still use · unless Nicolas extends the rule. Related: [[one-id-per-item]].
