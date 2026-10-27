---
name: arbinet-memory
description: General catch-all for arbinet project facts not recorded in the repo
metadata:
  type: project
---

Running list of arbinet facts. Append new ones here.

- **Stack:** **Node.js / TypeScript**
- **Universe:** ~15 venues × ~2000 instruments ≈ 30k pairs scanned.
- **Holding horizon:** seconds to days (spread strategies).
- **v1 venue set (decided 2026-08-06):** Binance, Bybit, OKX, Bitget, Gate, KuCoin — other ~9 venues later.
- **Architecture decisions (2026-08-06 interview, recorded in `research/orderbook-ws-connectivity/gap-analysis.md`):** no strategy→gateway request channel — one-way pub/sub only; dormant STALE books periodically auto-resync (limiter-bounded) instead of lazy read-triggered revalidation; Binance 24h rotation is staggered-with-dark-window, not make-before-break; normalization verification strictly cross-venue (single-venue assets stay unverified).
