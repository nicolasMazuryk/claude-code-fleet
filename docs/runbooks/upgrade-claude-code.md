# Upgrade Claude Code

Status: this repo installs the binary on both hosts ([ADR 0002](../decisions/0002-ownership-split.md), Phase 4b). Cloud:
`install.sh cloud` runs the native installer (`curl -fsSL https://claude.ai/install.sh | bash` as `agent`) only when
`~/.local/bin/claude` is missing; after that Claude Code updates itself (`autoUpdates`), like on the Mac.
oci no longer installs or updates Claude Code.

1. Mac: `claude update` (or it auto-updates). Check `claude --version`.
2. Cloud: `ssh cloud 'claude update && claude --version'` (or let it auto-update: `ls ~/.local/share/claude/versions`).
3. Restart long-running servers so they pick up the new binary:
   - Mac: `launchctl kickstart -k gui/$(id -u)/cc-orchestrator.claude.agents`, then `tmux kill-session -t rc && rc-servers`.
   - Cloud: `ssh cloud 'sudo systemctl restart cc-agents "cc-rc@*"'`. Sessions served by an RC server are archived on
     restart (transcripts/worktrees stay).
4. Re-check flags the scripts rely on: `claude remote-control --help` (`--spawn worktree`, `--name`,
   `--remote-control-session-name-prefix`, `--no-create-session-in-dir`), `claude agents --json`.
5. `make doctor` on both hosts. Note the tested version in `docs/progress/` if anything changed.
