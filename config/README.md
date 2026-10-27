# config/

| Path | What | Phase |
|---|---|---|
| `claude/settings.orchestrator.json` | keys this repo enforces on the Mac (deep-merged by `install.sh mac`) | 0 (content), 3 (apply) |
| `claude/cloud-settings.json` | cloud-only overrides merged by `cc-sync-settings` | 0 (content), 4 (apply) |
| `claude/mac-only.json` | Mac-only plugins and permission rules `cc-sync-settings` never sends to cloud | 4 |
| `claude/settings.mac.json` | `~/.claude/settings.json`, sanitized (credential-like `env` keys and `agent-push.sh` handlers dropped) | 1 (`make capture`) |
| `claude/statusline-*.sh`, `claude/sounds/`, `claude/plugins/claude-hud/`, `claude/ccstatusline/settings.json` | statusline scripts, Choo Choo sound, claude-hud wrapper + config, `~/.config/ccstatusline/settings.json` (verbatim) | 1 (`make capture`) |
| `claude/skills.txt`, `claude/skills/<name>/` | skill inventory (local / link / claude.ai synced) + copies of the local skills | 1 (`make capture`) |
| `claude/plugins.json` | marketplaces + installed plugins (id, scope, version, project, enabled) | 1 (`make capture`) |
| `claude/keybindings.json`, `agents/`, `commands/`, `output-styles/` | captured if present on the Mac (none today) | 1 |
| `mac/zshrc.captured` | the `# Claude Code` and `# Tailscale…` blocks of `~/.zshrc` (reference, not sourced) | 1 (`make capture`) |
| `claude/CLAUDE.md` | global preferences, agent rules, `@~/.claude/profile/*` imports → `~/.claude/CLAUDE.md` (`install.sh mac`) | 3 |
| `claude/profile/` | captured global profile (`~/.claude/profile/`, plaintext, ADR 0006); restored where missing | 3 |
| `claude/memory/<dir>/` | captured project memories (`~/.claude/projects/<dir>/memory/`); restored where missing | 3 |
| `mac/` | `config.tmpl` (→ `~/.config/cc-orchestrator/config`), `repos.txt`, `tmux.conf`, `zshrc.snippet` (`am`, `ac`), `ssh_config.snippet` (`Host cloud`), `cmux.json`, `launchd/*.plist.tmpl` (`@HOME@`, `@TMUX@`); `sshd-100-keys-only.conf` (→ `/etc/ssh/sshd_config.d/100-keys-only.conf` via `mac-remote-access apply`) | 1, 3, 6 |
| `cloud/` | `config.tmpl` (→ `~/.config/cc-orchestrator/config` on cloud), `repos.txt`, `systemd/{cc-agents.service,cc-rc@.service}`, `rsyslog-cc-orchestrator.conf` (→ `/etc/rsyslog.d/30-cc-orchestrator.conf`) | 4 |
| `tailscale/policy.hujson` | full tailnet policy as applied | 2 |
| `iphone/hosts.md` | Moshi hosts (address, user, auth, mosh-server, startup command), app settings | 6 |

No secrets here, ever (`make test` checks).
