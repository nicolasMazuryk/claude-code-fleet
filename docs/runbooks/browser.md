# Runbook: browser-router on the fleet

Design: [ADR 0007](../decisions/0007-browser-router-control-plane.md). The CLI, skill and hook live in `~/Documents/browser-router`;
this repo owns the relay, the cloud install, the drain timer and the settings wiring.

## What runs where
| | Mac | Cloud |
|---|---|---|
| relay | `agent-relay` (LaunchAgent) sends `mac-up` every 15 s, runs `browser-relay-handler` for lease/release/dispatch | `browser-relay-cloud line` (called by the relay's remote script) writes `mac-up` and `replies/<id>` |
| CLI | – | `~/.local/bin/browser-router` (`~/.local/share/browser-router`) and `agent-browser` |
| queue | – | `browser-router-vault-drain.timer` every 3 min |
| config | `~/.config/browser-router/sites.yaml` (source) | mirrored by `cc-sync-settings` |

## Install / update
1. Mac: `./install.sh mac` (copies `browser-up` + `browser-relay-handler` next to `agent-relay` in `~/.local/libexec/cc-orchestrator/`,
   registers the guard hooks and the `browser-router-relay` SessionStart slot, restarts the relay).
2. `cc-sync-settings` (mirrors settings with `CLAUDE_CODE_ENABLE_CFC=1`, the relay slot, and `sites.yaml`).
3. `./install.sh cloud` (human step, pushes the checkout and runs `cloud-local`: clone + build browser-router, install
   agent-browser, units + timer). `CC_INSTALL_NO_BROWSER=1` skips the browser step.

## Use
- Lease a Mac Chrome profile from cloud: `browser-relay-cloud lease <site> <profile> [--session <sid>] [--ttl 900]` prints `<id> <port>`
  (CDP on cloud's `127.0.0.1:<port>`); `browser-relay-cloud release <id>` ends it. Exit 5: Mac down, refused, or no answer.
- Check what the Mac reports: `ssh cloud 'cat ~/.local/state/agent-events/mac-up'` (fresh = mtime under 45 s).
- Vault drain by hand: `ssh cloud browser-vault-drain`; logs: `journalctl -u browser-router-vault-drain`.

## Egress gateway (Browser Use through our IP)
Design: [ADR 0007](../decisions/0007-browser-router-control-plane.md) (exception for TCP 8443). Files: `config/cloud/egress/`
(`compose.yaml`, `guard.nft`, `guard.sh`, `gost.yaml`), units `cc-egress.service`, `cc-egress-bytes.{service,timer}`.
Order matters; `[H]` = human step.
1. `[H]` oci repo, G3: apply foundation then core, `make secret-put` for `core-secret-egress-proxy-password` and
   `core-secret-browser-use-api-key`, `make host-sync VM=cloud` (opens 8443 on the host, enables IP forwarding and
   `--advertise-exit-node`).
2. `[H]` Tailscale admin: apply the updated `config/tailscale/policy.hujson` ([tailscale.md](tailscale.md) §6); create an OAuth
   client or auth key tagged `tag:egress` for the first join.
3. `[H]` Mac Keychain, once: `security add-generic-password -U -s cc-egress-proxy-password -a "$USER" -w` (the same password
   as in Vault) and, for the first join, `security add-generic-password -U -s cc-egress-ts-authkey -a "$USER" -w`.
4. `./install.sh cloud` delivers both to `cloud:~/.config/egress/` over the Mac-opened ssh (`bin/egress-secrets-push`;
   the proxy password is `gost-auth`: `browseruse <password>`, 0400, uid 10001), installs the units and starts
   `cc-egress` once `gost-auth` exists. The cloud cannot read that Vault secret (IAM option B); re-run the install after
   rotating it, then `ssh cloud sudo systemctl restart cc-egress`.
5. Exit node: `browser-router exit-node use <macbook|iphone|cloud|static-ip|none> --for egress` (replaces the old
   `staticipup`/`staticipdown` aliases). A node acting as an exit node cannot use one at the same time.
- TLS: gost generates a self-signed certificate at start; to serve a real one, add `certFile`/`keyFile` to the
  listener's `tls` block in `gost.yaml` and mount the files.
- Daily bytes: `EGRESS_DAILY_BYTES` (default 5 GiB) in `cc-egress-bytes.service`; the alert is a push via `agent-push`, only when you are away.
- Bought ISP proxy: uncomment the `chains:` block and `chain: upstream` in `gost.yaml`; credentials never go in git.
- Logs: `docker logs egress-gost-1`; `journalctl -u cc-egress`. If tailscale restarts alone, `sudo systemctl restart cc-egress`
  (gost and the guard share its namespace).

## Troubleshooting
| Symptom | Cause / fix |
|---|---|
| `skipped BrowserLease…: the Mac's hook changed` in `/tmp/agent-relay.log` | run `cc-sync-settings` (the relay handler's hash changed) |
| lease `chrome_missing`, `chrome_not_ready`, `forward_failed` | Chrome not installed / profile locked by a running Chrome / ControlMaster socket gone (relay reconnecting) |
| `no_free_port` | 100 leases held: release stale ones (`~/.local/state/browser-router/relay/leases/`) |
| `browser-relay-cloud sum` fails | the synced settings lack the `browser-router-relay` group: `./install.sh mac` then `cc-sync-settings` |
| clients connect but get no reply | the reply-routing rule is missing: `docker exec egress-guard-1 ip rule show` must list `fwmark 0x2/0x2 lookup main`; restart `egress-guard-1` |
| gost down, guard unhealthy | `docker logs egress-guard-1` (nft error); gost stays down by design (fail closed) |
| timer not active | browser-router not installed on cloud: `./install.sh cloud` |
