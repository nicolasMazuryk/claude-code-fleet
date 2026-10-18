# 0006 — The global profile lives in `~/.claude/profile/`, outside git

- Status: accepted (2026-10-18)
- Plan: global profile vs project memory

## Context
Claude Code auto-memory is keyed by the project path, so repo renames orphan it, and nothing in it applies across
repos. Facts about the owner (role, goals, career targets, working style, how the devices connect) belong in every
session on both hosts. This repo and `oci-free-tier-platform` are public on GitHub, so personal text must not enter
either one.

## Decision
- The profile is a set of Markdown files in `~/.claude/profile/` on the Mac (`me`, `career`, `goals`,
  `working-style`, `environments`). The Mac is the source of truth; they are edited there in place.
- `config/claude/CLAUDE.md` (installed as `~/.claude/CLAUDE.md`) imports them with `@~/.claude/profile/<file>.md`
  lines. Those import lines are the only trace in git.
- `cc-sync-settings` mirrors `profile` to cloud with the other `~/.claude` items (`rsync --delete`). `cc-capture`
  does not capture it.
- Project memory (`~/.claude/projects/<path>/memory/`) keeps only project-specific facts. Cross-project rules are
  promoted into `working-style.md`.

## Consequences
- Every session on both hosts loads the profile; a missing file only drops that import.
- The profile is not rebuildable from this repo. It is restored from a local backup or Time Machine, and cloud gets
  it back on the next `make sync`.
- `install.sh mac` never overwrites the profile, because it only writes `~/.claude/CLAUDE.md`.
- Verify row 3j checks Mac ↔ cloud parity.
