# Upgrade Claude Code

Status: Phase 4 decides who installs the cloud binary (recommendation: this repo, [ADR 0002](../decisions/0002-ownership-split.md)).

1. Mac: `claude update` (or it auto-updates). Check `claude --version`.
2. Cloud: `ssh cloud 'claude update && claude --version'`.
3. Restart long-running servers so they pick up the new binary:
   - Mac: `launchctl kickstart -k gui/$(id -u)/cc-orchestrator.claude.agents`, then `tmux kill-session -t rc && rc-servers`.
   - Cloud: `ssh cloud 'sudo systemctl restart cc-agents "cc-rc@*"'`. Sessions served by an RC server are archived on
     restart (transcripts/worktrees stay).
4. Re-check flags the scripts rely on: `claude remote-control --help` (`--spawn worktree`, `--name`,
   `--remote-control-session-name-prefix`, `--no-create-session-in-dir`), `claude agents --json`.
5. `make doctor` on both hosts. Note the tested version in `docs/progress/` if anything changed.
