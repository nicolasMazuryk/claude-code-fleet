# iPhone: hosts and app settings (no secrets here)

Procedure: [docs/runbooks/iphone-setup.md](../../docs/runbooks/iphone-setup.md).

## Moshi hosts (Blink: same values)

| Name | Host (MagicDNS) | User | Auth | mosh | mosh-server | Startup command |
|---|---|---|---|---|---|---|
| `cloud` | `cloud` (`cloud.tailnet-example.ts.net`) | `agent` | Tailscale SSH: no key, no password | on | default (`mosh-server` on PATH) | `tmux -u new -A -s fleet ~/.local/bin/agents-loop` (or type `ac`) |
| `mac` | `macbook` (`macbook.tailnet-example.ts.net`) | `nicolas` | Moshi Ed25519 key (public half in the Mac's `~/.ssh/authorized_keys`; keys only) | on | `/opt/homebrew/bin/mosh-server` | `/opt/homebrew/bin/tmux -u new -A -s agents ~/.local/bin/agents-loop` (or type `am`) |

mosh needs UDP 60000–61000: on cloud only on `tailscale0` (oci iptables); on the Mac the Application Firewall allows
the current mosh-server Cellar path (`mac-remote-access status`).

## Apps

| App | Setting |
|---|---|
| Tailscale | tailnet `tailnet-example`, VPN on (On Demand recommended) |
| Moshi | extra-keys row on (Esc, Ctrl, arrows, Tab) |
| ntfy | subscribed to the topic in `~/.config/agent-push/topic` on the Mac (server `ntfy.sh`); notifications allowed |
| Claude | same claude.ai account; Code tab lists `mac/<repo>` and `cloud/<repo>`; iOS notifications for Claude **off** |
| claude.ai (optional) | Settings → Require trusted devices |
