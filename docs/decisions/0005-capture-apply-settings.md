# 0005 — `~/.claude` is managed by capture/apply, not symlinks

- Status: accepted (2026-10, plan default)
- Plan: Phases 1, 3, 4

## Context
The repo must be able to rebuild the Mac's Claude Code configuration. Claude Code rewrites `settings.json`
atomically (write temp + rename), which replaces a symlink with a regular file and silently detaches it from the repo.
The Mac settings also hold machine-local and possibly secret values.

## Decision
- `bin/cc-capture` snapshots the curated Mac files (`settings.json`, `statusline-combined.sh`, `sounds/`, skill and
  plugin lists, relevant `~/.zshrc` aliases) into `config/claude/` and `config/mac/`, **sanitized** (tokens/keys
  removed), and shows a git diff for review.
- `install.sh mac` applies them back: backs up, then deep-merges `config/claude/settings.mac.json` and
  `config/claude/settings.orchestrator.json` (the keys this repo enforces) into `~/.claude/settings.json`.
- `cc-sync-settings` keeps the spec's Mac → cloud mirror, transforming as needed.
- Scripts in `bin/` *are* symlinked into `~/.local/bin` (Claude Code never rewrites them).

## Consequences
- The Mac remains the source of truth; the repo is a reviewed snapshot. Drift is detected by `cc-doctor`.
- Hand edits on the Mac must be followed by `make capture` + commit, or they are lost on a rebuild.
