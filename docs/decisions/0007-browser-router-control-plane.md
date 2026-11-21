# 0007 — browser-router: each host browses on its own; cloud never drives the Mac browser

- Status: accepted (2026-10-21)
- Plan: browser-router (`~/code/browser-router`, contracts in its `docs/contracts.md`)

## Context
Agents on both hosts need logged-in browsers (headed Chrome profiles, Dia with the Claude extension, Computer Use on the
Mac; Browser Use Cloud from anywhere). The Mac must stay unreachable from cloud (invariant 4).

## Decision
- **The cloud brain never drives the Mac browser.** No lease, port forward, dispatch or status marker crosses from cloud
  to the Mac's browsers. `agent-relay` carries only hook events (sounds) and the presence beacon. On cloud, browser-router
  runs shield sites on Browser Use Cloud and blocks vault sites, loopback sites and an explicitly named Mac executor; a
  task that needs the Mac's logged-in browser runs in a Mac session. A cloud → Mac browser channel (CDP reverse forwards
  over the relay's ssh, relayed vault dispatch) is not used because it lets an `auto`-mode cloud agent act in the Mac's
  logged-in profiles, needs a hash-checked handler slot and a Mac status marker on cloud, and fails whenever the Mac
  sleeps.
- **Vault jobs never queue.** `browser-router vault submit` starts the job now under the host's global lock (hours, caps,
  gap and Dia apply) or exits 5 with the reasons. There is no drain timer or LaunchAgent: a queue would run jobs at a
  time nobody watches, and the caller retrying is simpler than per-host queue state.
- **Selftest drift only warns.** A passing selftest record stays trusted after a browser, extension or agent-browser
  update; `route`, `status` and `doctor` show the warning. Nothing re-qualifies in the background.
- **Install.** `install.sh cloud-local` clones browser-router to `~/.local/share/browser-router` (fast-forward, built by
  `pnpm install --frozen-lockfile && pnpm build`, linked to `~/.local/bin/browser-router`) and installs agent-browser pinned
  (`AGENT_BROWSER_VERSION`, 0.39.1) with `npm -g` + `agent-browser install`, then installs the browser-router plugin from
  that checkout (`claude plugin marketplace add ~/.local/share/browser-router`, `claude plugin install
  browser-router@browser-router --scope user`). `CLAUDE_CODE_ENABLE_CFC=1` is set in cloud's settings env so
  `claude -p --chrome` works.
- **Hooks.** The browser-router skill and the browser-guard hook ship as the Claude Code plugin `browser-router@browser-router`,
  from the local directory marketplace `browser-router` in the browser-router checkout (`.claude-plugin/marketplace.json` →
  `./plugin`). The plugin's `hooks/hooks.json` registers `${CLAUDE_PLUGIN_ROOT}/hooks/browser-guard` as PreToolUse for
  `mcp__claude-in-chrome__`, `mcp__computer-use__`, `Bash` (agent-browser) and the Peekaboo MCP with `onFailure: "block"`
  (fail closed; the launcher finds `node` without the interactive PATH), as PostToolUse for the Chrome tab tools
  (`tabs_create_mcp|tabs_close_mcp|tabs_context_mcp|navigate`) and as Stop. The plugin, not `settings.json`, owns these
  hooks, so they load the same way on both hosts and update with the checkout. On the Mac `make install` in browser-router
  adds the marketplace (`~/code/browser-router`) and installs the plugin; `install.sh mac` removes any browser-guard
  handler (and any `browser-router-relay` SessionStart group) from `settings.json` so nothing runs twice or points at a
  missing script. On cloud `install.sh cloud-local` installs it (above), and `config/claude/cloud-settings.json` points
  `extraKnownMarketplaces.browser-router` at `~/.local/share/browser-router`, because the Mac's path rewritten under
  cloud `$HOME` does not exist there.
- **sites.yaml.** `~/.config/browser-router/sites.yaml` on the Mac is mirrored to cloud by `cc-sync-settings`.

## Consequences
- A sleeping Mac or a dead relay never blocks cloud browser work: cloud only uses Browser Use Cloud.
- Vault and Mac-only sites are done from a Mac session; cloud refuses them with a clear reason.
- `install.sh` removes the units and LaunchAgents this repo does not ship (`OLD_UNITS`, `OLD_LAUNCHD`).

## Browser Use egress: Polish ISP proxy, no self-hosted gateway
Browser Use browsers must present one stable Polish IP to a site (spec §6). They connect **directly through a persistent
Polish ISP proxy**, set once per host with `browser-router proxy set <url>` (a human step, the URL is a secret) and checked
with `browser-router proxy status` / `probe`; a site with `isp_pin` always exits from the same proxy IP. Until that
proxy exists, Browser Use's own `pl` residential proxy is used.

- **No ingress, invariant 3 intact.** Cloud opens no public port for this. There is no exception to invariant 3.
- **No self-hosted gateway.** An egress gateway on cloud (a TLS CONNECT proxy in front of a tailscale exit node) is not used:
  Browser Use cannot speak TLS to a custom proxy, so such a gateway cannot be used from Browser Use at all, and it would
  have required public ingress on TCP 8443 plus a certificate pipeline. The ISP proxy needs none of that.
- **Secrets.** The proxy URL is stored by browser-router on the host that needs it and never enters git. The Browser Use
  key (`core-secret-browser-use-api-key`) stays readable by cloud: the cloud brain calls Browser Use; the Mac's copy is
  `~/.config/browser-router/env`, written from the Keychain by `bin/browser-router-env-push`.
- **Tailnet.** macbook, iPhone and cloud are exit nodes; the Mac picks its own with `tailscale set --exit-node=<node>`
  (tailscale runbook §6); `cloud` is the static egress IP. browser-router does not switch exit nodes. The policy has no
  rule with `src: tag:cloud` and no other tag for egress.
- **Retiring the earlier gateway.** The commands to switch off any previously deployed instance are in
  [browser.md](../runbooks/browser.md) (decommission section); they are human steps.
