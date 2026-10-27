---
name: orchestrator-merge-authority
description: "In the browser-router orchestration the user lets the orchestrator push, open PRs and merge FLEET/OCI PRs itself"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 4bcb2d5b-2168-432d-a8ed-3a7917bd135a
  modified: 2026-10-22T09:40:58.165Z
---

On 2026-10-22 the user said: "you can merge, PR and push whatever and whenever you want" (browser-router run).

**Why:** the user doesn't want to be the bottleneck. The auto-mode classifier blocked relayed merges and pushes in implementer sessions.

**How to apply:** after a job's verifier PASSes (and CI is green), push, open the PR and merge it, from the orchestrator if needed. Terraform apply, host-sync, writing secrets, spending money and GUI work stay human-only. Related: [[orchestrator-gates]]
