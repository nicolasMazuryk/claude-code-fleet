# bin/

Scripts symlinked into `~/.local/bin` on both hosts by `install.sh` (editing them here changes what runs).
| Script | What | Phase |
|---|---|---|
| `agent-env` | sourced: PATH, UTF-8, node (nvm on the Mac), `~/.config/cc-orchestrator/config` | 3 |
| `agents-loop` | Agent View, restarted after Esc, from `$AGENTS_ROOT` | 3 |
| `rc-serve <dir>` | one Remote Control server (`$AGENT_HOST/<repo>`, `--spawn worktree`) | 3 |
| `rc-servers` | reconcile servers with `$REPOS_FILE` (Mac: tmux `rc`; cloud: `cc-rc@`) | 3 |
| `cc-orchestrator-start` | Mac login: tmux `agents` + `rc-servers` (run by the LaunchAgent via tmux) | 3 |
| `repo-init [--rc] [--no-trust] <repo>` | `.gitignore`/`.worktreeinclude`, trust, allowlist, servers | 3 |
| `fleet [logs\|restart\|attach <host> <repo>]` | all sessions on both hosts | 3 |
| `agent-present` | exit 0 when you're at the Mac (used by `hooks/agent-push.sh`) | 3 (verified in 5) |
| `cc-capture` | snapshot Mac `~/.claude` → `config/` | 1 |
| `cc-sync-settings`, `cc-relay-hook`, `agent-relay` | settings mirror, sound relay | 4–5 |
| `cc-doctor` | health check | 7 |

Rules: `#!/usr/bin/env bash`, idempotent, shellcheck-clean (`make lint`), bash 3.2 compatible if it runs on the Mac.
