---
name: e2e-tiers
description: handyman e2e policy — smoke tier (<10 min) per verification, full tier (<30 min) once after major changes, ~90 % browser share only
metadata:
  type: feedback
---

handyman e2e runs in two tiers, selected by `E2E_TIER` in `playwright.config.ts`:
- **smoke** (`E2E_TIER=smoke PORT=<port> pnpm e2e`, < 10 min, ~90 % of the important checks): every verification and PR CI. Projects: phone-393 (iPhone 15, WebKit), phone-pixel-412 (Pixel 7, Chromium), desktop-1280 (Chromium); no `@shots`, no faq-nojs.
- **full** (`PORT=<port> pnpm e2e`, < 30 min): only once after major changes (final acceptance), plus `workflow_dispatch` and the weekly CI cron. Adds phone-small-360, phone-se-375, tablet-768, tablet-landscape-1024, desktop-1440.
- Browsers: only engines covering ~90 % of real usage, desktop + mobile (StatCounter Poland: Chromium ≈ 79 % + WebKit ≈ 12 %). Firefox and desktop Safari are not tested; never 12+ browser projects. Re-check current StatCounter share before changing the matrix.

**Why:** the user wants speed/quality balance; the 13-project suite took 15–20 min per run and was repeated by every verifier. This applies to the handyman project only, not globally.
**How to apply:** verifiers and implementers run smoke; run full once at the end of a major change, together with LHCI.
