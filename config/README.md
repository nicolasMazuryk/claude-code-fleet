# config/

| Path | What | Phase |
|---|---|---|
| `claude/settings.orchestrator.json` | keys this repo enforces on the Mac (deep-merged by `install.sh mac`) | 0 (content), 3 (apply) |
| `claude/cloud-settings.json` | cloud-only overrides merged by `cc-sync-settings` | 0 (content), 4 (apply) |
| `claude/settings.mac.json`, `statusline-combined.sh`, `sounds/`, `CLAUDE.md` | sanitized capture of the Mac's `~/.claude` | 1 |
| `mac/` | `config`, `repos.txt`, `tmux.conf`, `zshrc.snippet`, `ssh_config.snippet`, `cmux.json`, `sshd-100-keys-only.conf`, `launchd/*.plist.tmpl` | 1, 3, 6 |
| `cloud/` | `config`, `repos.txt`, `systemd/{cc-agents.service,cc-rc@.service}` | 4 |
| `tailscale/policy.hujson` | full tailnet policy as applied | 2 |
| `iphone/hosts.md` | Moshi hosts, ntfy, Claude app settings | 6 |

No secrets here, ever (`make test` checks).
