# Runbook: browser-router on the fleet

Design: [ADR 0007](../decisions/0007-browser-router-control-plane.md). The CLI, skill and hook live in `~/Documents/browser-router`;
this repo owns the relay, the cloud install, the drain timer and the settings wiring.

## What runs where
| | Mac | Cloud |
|---|---|---|
| relay | `agent-relay` (LaunchAgent) sends `mac-up` every 15 s, runs `browser-relay-handler` for lease/release/dispatch | `browser-relay-cloud line` (called by the relay's remote script) writes `mac-up` and `replies/<id>` |
| CLI | `agent-browser` (pinned, `npm -g` under the nvm node, plus Chrome for Testing), installed by `install-mac`; browser-router comes from the `~/Documents/browser-router` checkout via a global link | `~/.local/bin/browser-router` (`~/.local/share/browser-router`) and `agent-browser` |
| queue | – | `browser-router-vault-drain.timer` every 3 min |
| config | `~/.config/browser-router/sites.yaml` (source) | mirrored by `cc-sync-settings` |

## Browser profiles (Mac)
| Browser | Profile | Used for |
|---|---|---|
| Dia | `vault-extension` | Claude in Chrome; Google accounts, OCI console |
| Dia | `vault-screen` | no extensions; LinkedIn via computer use |
| Chrome | `shield-extension` | Claude in Chrome; mac-chrome shield profile, no sites assigned |

Leased Chrome profiles (`~/.chrome-agent-profiles/<profile>`) are separate from these.

## Install / update
1. Mac: `./install.sh mac` (copies `browser-up` + `browser-relay-handler` next to `agent-relay` in `~/.local/libexec/cc-orchestrator/`,
   registers the guard hooks and the `browser-router-relay` SessionStart slot, restarts the relay, and installs the pinned
   `agent-browser@0.39.1` + `agent-browser install`; a rerun prints ok and changes nothing; `CC_INSTALL_NO_BROWSER=1` skips it).
2. `cc-sync-settings` (mirrors settings with `CLAUDE_CODE_ENABLE_CFC=1`, the relay slot, and `sites.yaml`).
3. `./install.sh cloud` (human step, pushes the checkout and runs `cloud-local`: clone + build browser-router, install
   agent-browser, units + timer). `CC_INSTALL_NO_BROWSER=1` skips the browser step.
   On Linux ARM64 (cloud) Chrome for Testing does not exist, so the step installs Playwright's Chromium
   (`playwright@1.63.0 install-deps chromium`, then `install chromium` into `~/.cache/ms-playwright`) and sets
   `executablePath` in `~/.agent-browser/config.json`; a rerun changes nothing. macOS runs `agent-browser install` as before.

## Use
- Lease a Mac Chrome profile from cloud: `browser-relay-cloud lease <site> <profile> [--session <sid>] [--ttl 900]` prints `<id> <port>`
  (CDP on cloud's `127.0.0.1:<port>`); `browser-relay-cloud release <id>` ends it. Exit 5: Mac down, refused, or no answer.
- Check what the Mac reports: `ssh cloud 'cat ~/.local/state/agent-events/mac-up'` (fresh = mtime under 45 s).
- Vault drain by hand: `ssh cloud browser-vault-drain`; logs: `journalctl -u browser-router-vault-drain`.

## Unregistered sites
A host with no `sites.yaml` entry matches only `"*"`. The agent classifies the task and routes with `--identity anonymous|personal`.
- Anonymous (no login, none of the user's own data, read-only public pages): runs on the `"*"` default.
- Personal (acting as the user or on the user's data or money, or any other risk), or `--identity` missing: `route` is blocked (exit 7) and lists the configuration choices. A human picks one
  (tier vault|shield, executor, profile, optional `--egress-pin`, `--caps`, `--logged-in`), then
  `browser-router site add <host> --tier … --executor …` writes the entry to the registry file the symlink points at
  (`~/Documents/browser-router/config/sites.yaml`). Commit that change in the browser-router repo, run `cc-sync-settings`
  to mirror it to cloud, then route again. Background sessions stop with "needs input: site config for <host>".

## Browser Use proxy (Polish ISP proxy)
Design: [ADR 0007](../decisions/0007-browser-router-control-plane.md). Browser Use browsers go direct through a persistent
Polish ISP proxy, so a site sees one stable Polish residential IP. Until that proxy exists, use Browser Use's own `pl`
residential proxy. There is no self-hosted gateway on cloud and no public ingress.
1. `[H]` Buy a persistent (static) Polish ISP proxy and note its URL (`scheme://user:pass@host:port`).
2. `[H]` `browser-router proxy set <url>` on each host that starts Browser Use sessions. The URL is a secret: it is stored by
   browser-router (never in git, never on argv in logs). The command prompts or reads stdin, per `browser-router proxy --help`.
3. Check: `browser-router proxy status` (configured, no credentials shown) and `browser-router proxy probe` (exits through
   the proxy and prints the IP and country; expect a Polish residential IP, the same on every run).
4. Browser Use API key: Mac Keychain `cc-browser-use-api-key`; `./install.sh mac` and `./install.sh cloud` write it to
   `~/.config/browser-router/env` (0600, key `BROWSER_USE_API_KEY`) via `bin/browser-router-env-push`. A missing item skips
   the key with a log line; re-run both installs after adding it.
- Exit nodes for the Mac itself (not for Browser Use): `browser-router exit-node use <macbook|iphone|cloud|static-ip|none> --for self`
  ([tailscale.md](tailscale.md) §7).

## Decommission the egress gateway (human, once; do not script)
The self-hosted egress gateway (gost, nftables guard, tailscale sidecar, Mac certificate renewal) is not used. After this
change is merged and `./install.sh mac` and `./install.sh cloud` have run, retire the live parts by hand:
1. Cloud: `ssh cloud 'sudo systemctl disable --now cc-egress.service cc-egress-bytes.timer'`, then
   `ssh cloud 'docker compose -p egress down'`; optionally remove `/etc/systemd/system/cc-egress*.service`,
   `cc-egress-bytes.timer`, `sudo systemctl daemon-reload`, and `~/.config/egress`, `~/.local/state/egress`.
2. Mac: `launchctl bootout gui/$(id -u)/cc-orchestrator.claude.egress-cert`, then delete
   `~/Library/LaunchAgents/cc-orchestrator.claude.egress-cert.plist` and
   `~/.local/libexec/cc-orchestrator/egress-cert-renew`; Keychain: delete `cc-egress-proxy-password`,
   `cc-egress-ts-authkey`, `cc-egress-public-host`, `cc-cf-acme-dns-token`; optionally `brew uninstall lego`.
3. OCI Vault: remove `core-secret-egress-proxy-password` (and the egress join key if one was stored).
4. Tailscale admin: apply the updated `config/tailscale/policy.hujson` ([tailscale.md](tailscale.md) §6) and delete the
   machine `egress`.
5. `oci-free-tier-platform`: close TCP 8443 (NLB listener, NSG rule, host rule), drop the `egress.mazuryktech.com`
   record, and revert the IP-forwarding/exit-node bits only if nothing else uses them (cloud stays an exit node for the
   Mac). That is a terraform change in that repo (job J27, its own PR); apply is human.

## Troubleshooting
| Symptom | Cause / fix |
|---|---|
| `skipped BrowserLease…: the Mac's hook changed` in `/tmp/agent-relay.log` | run `cc-sync-settings` (the relay handler's hash changed) |
| lease `chrome_missing`, `chrome_not_ready`, `forward_failed` | Chrome not installed / profile locked by a running Chrome / ControlMaster socket gone (relay reconnecting) |
| `no_free_port` | 100 leases held: release stale ones (`~/.local/state/browser-router/relay/leases/`) |
| `browser-relay-cloud sum` fails | the synced settings lack the `browser-router-relay` group: `./install.sh mac` then `cc-sync-settings` |
| `browser-router: Permission denied` | `dist/cli.js` lost its exec bit: `./install.sh cloud` (step_browser sets it) |
| timer not active | browser-router not installed on cloud: `./install.sh cloud` |
