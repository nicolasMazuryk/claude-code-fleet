# 0006 — The global profile and project memories are captured into this repo

- Status: accepted (2026-10-18, owner's decision)
- Plan: global profile vs project memory

## Context
Claude Code auto-memory is keyed by the project path, so repo renames orphan it, and nothing in it applies across
repos. Facts about the owner (role, goals, career targets, working style, how the devices connect) belong in every
session on both hosts, and rebuilding the Mac must restore them from this repo like the rest of `~/.claude`.

## Decision
- The global profile is a set of Markdown files in `~/.claude/profile/` on the Mac (`me`, `career`, `goals`,
  `working-style`, `environments`, plus `claude-ai-paste.txt` for the claude.ai apps). `~/.claude/CLAUDE.md`
  (`config/claude/CLAUDE.md`) holds the global preferences and imports the profile with `@~/.claude/profile/<file>.md`.
- Project memory (`~/.claude/projects/<dir>/memory/`) keeps only project-specific facts; cross-project rules live in
  `working-style.md`, and the sequential-escalation rule for phased work lives in the `orchestrate` skill.
- `cc-capture` copies `profile/` to `config/claude/profile/` and every non-empty project memory to
  `config/claude/memory/<dir>/` (mirrored: deletions on the Mac are deleted in the repo). Session transcripts are
  never captured. The secret-pattern scan applies to both; it aborts the capture on a match.
- The repo is public and the files are captured in **plaintext**. The owner accepted that the profile (career
  targets, compensation floor, employer) and the memories (host names, server addresses) are publicly readable.
- `install.sh mac` restores profile files and memory folders only where they are missing; it never overwrites Mac
  state. `cc-sync-settings` mirrors `profile/` to cloud (`rsync --delete`).

## Consequences
- Every session on both hosts loads the profile; a Mac rebuild gets it back from the repo.
- Profile and memory edits on the Mac need `make capture` + commit, or they are lost on a rebuild (`cc-doctor`
  reports the drift).
- Anything written to the profile or a memory is published on the next capture. Secrets never go there (invariant 1).
- Verify row 3j checks Mac ↔ cloud parity of the profile.
