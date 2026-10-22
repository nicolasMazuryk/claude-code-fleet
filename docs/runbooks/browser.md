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

## Troubleshooting
| Symptom | Cause / fix |
|---|---|
| `skipped BrowserLease…: the Mac's hook changed` in `/tmp/agent-relay.log` | run `cc-sync-settings` (the relay handler's hash changed) |
| lease `chrome_missing`, `chrome_not_ready`, `forward_failed` | Chrome not installed / profile locked by a running Chrome / ControlMaster socket gone (relay reconnecting) |
| `no_free_port` | 100 leases held: release stale ones (`~/.local/state/browser-router/relay/leases/`) |
| `browser-relay-cloud sum` fails | the synced settings lack the `browser-router-relay` group: `./install.sh mac` then `cc-sync-settings` |
| timer not active | browser-router not installed on cloud: `./install.sh cloud` |
