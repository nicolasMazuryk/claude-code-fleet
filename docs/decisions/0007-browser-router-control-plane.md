# 0007 — browser-router: the relay carries browser leases and dispatches

- Status: accepted (2026-10-21)
- Plan: browser-router (`~/Documents/browser-router`, contracts in its `docs/contracts.md` §7)

## Context
Cloud agents need a real, logged-in browser on the Mac (headed Chrome profiles, Dia with the Claude extension, Computer
Use). The Mac must stay unreachable from cloud (invariant 4).

## Decision
- **One connection, still opened by the Mac.** `agent-relay`'s ssh to `cloud` is also the ControlMaster
  (`~/.local/state/agent-relay/cm.sock`, dir 0700). Nothing on cloud ever dials the Mac.
- **Upstream (Mac → cloud), same ssh:** a `mac-up <json>` line every beacon (`bin/browser-up`: Dia/Chrome running,
  versions, executors) which cloud writes to `~/.local/state/agent-events/mac-up` (stale after 45 s), and one-line replies
  (`lease-ready`, `lease-failed`, `release-ok`, `dispatch-ok`, `dispatch-done`) spooled by the handler and flushed each
  second. `bin/browser-relay-cloud line` validates every line; port must be 9300–9399; ids are `[A-Za-z0-9_-]`.
- **Downstream (cloud → Mac), same event stream as the hook relay:** `BrowserLease`, `BrowserRelease`, `BrowserDispatch`
  lines in `events.jsonl`. Cloud names a handler slot, never a command: the SessionStart group with matcher
  `browser-router-relay` (a source Claude Code never reports) in the Mac's `~/.claude/settings.json`, hash-checked like any
  relayed handler. `cc-sync-settings` copies that group to cloud unchanged so the sum matches.
- **CDP reverse forward.** On a lease the Mac starts headed Chrome on `~/.chrome-agent-profiles/<profile>` with
  `--remote-debugging-port=<9300–9399> --remote-debugging-address=127.0.0.1` and runs
  `ssh -S <cm.sock> -O forward -R 127.0.0.1:<p>:127.0.0.1:<p> cloud` on the ControlMaster. Cloud gets a loopback-only port;
  the forward is cancelled on release or when the ttl ends. The forward travels over the Mac-opened connection, so the
  tailnet policy still has no rule with `src: tag:cloud`.
- **Dispatch.** A `BrowserDispatch` for `mac-computer-use` runs `claude -p <task>` on the Mac, in the repo of the same
  name under `AGENTS_ROOT` (else `$HOME`), with the Mac's own permission settings; the task is one argv, never shell text.
  `dispatch-done` makes cloud run `browser-router vault finish`, freeing the global lock.
- **Vault queue.** `browser-router-vault-drain.timer` (every 3 min) starts at most one runnable job. It runs only once
  browser-router is installed. `CLAUDE_CODE_ENABLE_CFC=1` is set in cloud's settings env so `claude -p --chrome` works.
- **Install.** `install.sh cloud-local` clones browser-router to `~/.local/share/browser-router` (fast-forward, built by
  `pnpm install --frozen-lockfile && pnpm build`, linked to `~/.local/bin/browser-router`) and installs agent-browser pinned
  (`AGENT_BROWSER_VERSION`, 0.39.1) with `npm -g` + `agent-browser install`.
- **Hooks.** `~/.claude/hooks/browser-guard` (shipped by browser-router) is registered as PreToolUse for
  `mcp__claude-in-chrome__.*`, `mcp__computer-use__.*` and `Bash` (agent-browser) on the Mac; the settings sync carries it to cloud.
- **sites.yaml.** `~/.config/browser-router/sites.yaml` on the Mac is mirrored to cloud by `cc-sync-settings`.

## Consequences
- A dead relay, sleeping Mac or broken link means no `mac-up` marker: leases fail fast (exit 5), vault jobs wait.
- Cloud, which runs agents in `auto` mode, can drive a Mac Chrome profile through the leased port while the lease lasts.
  The profile is a bare name under `~/.chrome-agent-profiles`; the port range, ttl cap (4 h) and one lease per id bound it.
- Changing the Mac's relay handler needs `cc-sync-settings` (the sum changes), as for other relayed hooks.
- Verify rows 11a–11e check the relay, the lease/forward, the drain timer and the sites mirror.

## Browser Use egress: Polish ISP proxy, no self-hosted gateway
Browser Use browsers must present one stable Polish IP to a site (spec §6). They connect **directly through a persistent
Polish ISP proxy**, set once per host with `browser-router proxy set <url>` (a human step, the URL is a secret) and checked
with `browser-router proxy status` / `probe`. Until that proxy exists, Browser Use's own `pl` residential proxy is used.

- **No ingress, invariant 3 intact.** Cloud opens no public port for this. There is no exception to invariant 3.
- **No self-hosted gateway.** An egress gateway on cloud (a TLS CONNECT proxy in front of a tailscale exit node) is not used:
  Browser Use cannot speak TLS to a custom proxy, so such a gateway cannot be used from Browser Use at all, and it would
  have required public ingress on TCP 8443 plus a certificate pipeline. The ISP proxy needs none of that.
- **Secrets.** The proxy URL is stored by browser-router on the host that needs it and never enters git. The Browser Use
  key (`core-secret-browser-use-api-key`) stays readable by cloud: the cloud brain calls Browser Use; the Mac's copy is
  `~/.config/browser-router/env`, written from the Keychain by `bin/browser-router-env-push`.
- **Tailnet.** Cloud remains an exit node for the Mac (`browser-router exit-node use cloud --for self`, tailscale runbook §7).
  The policy has no rule with `src: tag:cloud` and no other tag for egress.
- **Retiring the earlier gateway.** The commands to switch off any previously deployed instance are in
  [browser.md](../runbooks/browser.md) (decommission section); they are human steps.
