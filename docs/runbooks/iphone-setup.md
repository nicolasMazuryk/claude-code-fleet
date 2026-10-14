# iPhone setup

Status: skeleton; completed in Phase 6. Host table: `config/iphone/hosts.md`.

1. Tailscale app → same tailnet (`tailnet-example`).
2. Moshi (alternative: Blink Shell). Generate a key; add its public key to the Mac's `~/.ssh/authorized_keys`.
3. Hosts:

   | Host | Address | User / auth | mosh server | Command on connect |
   |---|---|---|---|---|
   | `cloud` | `cloud` | `agent`, Tailscale SSH (no key) | default | `tmux -u new -A -s fleet ~/.local/bin/agents-loop` |
   | `mac` | `macbook` | `nicolas`, Moshi key | `/opt/homebrew/bin/mosh-server` | `tmux -u new -A -s agents ~/.local/bin/agents-loop` |

4. ntfy app → subscribe to the topic (read it on the Mac: `cat ~/.config/agent-push/topic`; never paste it into git or chat logs).
5. Claude app → same claude.ai account; Code tab lists `mac/<repo>` and `cloud/<repo>`; app notifications off.
6. Terminal extra-keys row on (arrows, Ctrl, Esc).
7. Optional: claude.ai → Require trusted devices.
8. Verify: [verify.md](verify.md) step 7.
