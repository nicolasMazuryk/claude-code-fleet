---
name: worktree-context-ephemeral
description: "Conductor worktree .context/ is ephemeral; long-lived artifacts go to the main checkout, gitignored"
metadata:
  type: feedback
---

Conductor workspaces are git worktrees — the gitignored `.context/` dir is **lost when the task/worktree is torn down**. Do not emit long-lived artifacts there.

**Why:** operator credentials (e.g. a WireGuard operator privkey/config) and any output meant to outlive the task must persist beyond the worktree.

**How to apply:** write durable artifacts into the **main (non-worktree) checkout** at `~/code/cross-exchange-arbitrage/`, and for secrets add a `.gitignore` rule so the secret file is never committed. Example chosen by the user: operator WireGuard config → `~/code/cross-exchange-arbitrage/wireguard/operator-wg0.conf` (mode 0600), with `wireguard/operator-wg0.conf` gitignored. Use `.context/` only for throwaway cross-agent scratch within the current task.
