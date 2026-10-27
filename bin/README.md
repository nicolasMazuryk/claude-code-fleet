# bin/

Scripts symlinked into `~/.local/bin` on both hosts by `install.sh` (editing them here changes what runs; on cloud
the links point into the rsync copy `~/claude-code-fleet`, refreshed by `./install.sh cloud`). Mac-only, not linked on
cloud: `cc-capture`, `cc-sync-settings`, `cc-orchestrator-start`, `agent-relay`, `mac-remote-access`. The relay LaunchAgent runs copies of
`agent-relay` and `agent-present` in `~/.local/libexec/cc-orchestrator/` (launchd can't read `~/Documents`);
`./install.sh mac` refreshes them.
| Script | What | Phase |
|---|---|---|
| `agent-env` | sourced: PATH, UTF-8, node (nvm on the Mac), `~/.config/cc-orchestrator/config` | 3 |
| `agents-loop` | Agent View, restarted after Esc, from `$AGENTS_ROOT` | 3 |
| `rc-serve <dir>` | one Remote Control server (`$AGENT_HOST/<repo>`, `--spawn worktree`); loops on the Mac, `exec`s once under systemd | 3, 4b |
| `rc-servers` | reconcile servers with `$REPOS_FILE` (Mac: tmux `rc`; cloud: `cc-rc@` for cloned + trusted repos, legacy `agent@` stopped first) | 3, 4b |
| `cc-orchestrator-start` | Mac login: tmux `agents` + `rc-servers` (run by the LaunchAgent via tmux) | 3 |
| `repo-init [--rc] [--no-trust] <repo>` | `.gitignore`/`.worktreeinclude`, trust, allowlist, servers | 3 |
| `repo-tidy [--apply] [--no-remote] [--no-claude-state] [repo…]` | your repos (origin `github.com/$GH_OWNER`) under `$AGENTS_ROOT` and in Claude Code: sync default checkouts; remove merged worktrees/branches (bundled first) and stale Claude state; dry run by default. Driven by the `cleanup-all-repositories-state` skill | 3, 4b |
| `fleet [logs\|restart\|attach <host> <repo>]` | all sessions on both hosts | 3 |
| `agent-present` | exit 0 when you're at the Mac (Mac: `ioreg`; cloud: relay's `mac-present` marker < 90 s) | 3, 5 |
| `cc-capture` | snapshot Mac `~/.claude` → `config/` | 1 |
| `cc-sync-settings [--dry-run\|--print] [--install-plugins]` | Mac → cloud settings mirror (expect `4 … relayed`) | 4 |
| `cc-relay-hook` | cloud: queue a relayed Mac hook event for `agent-relay` | 4 (used in 5) |
| `agent-relay [--handle]` | Mac (LaunchAgent): one ssh to cloud; presence up, relayed hook events down; runs the Mac's own hash-checked handler | 5 |
| `mac-remote-access [status\|add-key <pub>\|selftest\|apply [--force]]` | Mac: phone access (Remote Login check, Moshi key, keys-only sshd drop-in, AC sleep, mosh firewall; `apply` uses sudo, lockout-guarded) | 6 |
| `cc-doctor [--local]` | health check: tools, config and links, units/LaunchAgents, RC servers = `repos.txt`, relay, ntfy topic, settings drift, Full Disk Access, mosh firewall, disk. On the Mac also cloud (`--local` there) and Mac → cloud settings parity. Exit 1 on any FAIL; never prints the topic | 7 |

Rules: `#!/usr/bin/env bash`, idempotent, shellcheck-clean (`make lint`), bash 3.2 compatible if it runs on the Mac.
