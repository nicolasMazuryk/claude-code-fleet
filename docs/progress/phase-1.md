# Phase 1 — Capture the current Mac state

Date: 2026-10-14 · Branch: `phase-1-capture` (stacked on `phase-0-foundation`)

## Done
- `bin/cc-capture` (`make capture`): stages a snapshot of the Mac, scans it for secrets, then mirrors it into
  `config/`. `--check` writes nothing and exits 1 on drift (for `cc-doctor`, Phase 7). Bash 3.2 / BSD-safe;
  `CC_CAPTURE_HOME` / `CC_CAPTURE_REPO` overrides for tests.
  - `settings.json` → `config/claude/settings.mac.json`. Credential-like `env` keys are dropped (none today), and so
    are `agent-push.sh` handlers, so the Phase 3 hook groups never leak into the baseline. The 4 `afplay` hooks stay.
  - Verbatim: `statusline-combined.sh`, `statusline-sys.sh`, `sounds/choo-choo.mp3`, the claude-hud wrapper
    `plugins/claude-hud/{statusline.mjs,config.json}`, and `~/.config/ccstatusline/settings.json`. The statusline
    depends on ccstatusline (npm global under nvm) and `statusline-sys.sh`, both found while capturing.
  - `skills.txt`: an inventory of the skills. 1 is local (`update-autoresearch-worktrees`, copied to
    `config/claude/skills/`), 1 is a link (`find-skills` → `~/.agents/skills`, with its source from
    `.skill-lock.json`), and 13 are claude.ai-synced (listed only).
  - `plugins.json`: 3 marketplaces and 4 plugins. These are the 3 user-scope plugins plus `playwright`, which is
    project-scoped in `~/Documents/datapipeline`.
  - `config/mac/zshrc.captured`: the `# Claude Code` block (`c`, `cc`, `ca`, `cw`, `cbg`) and the
    `# Tailscale static IP` block (`staticipup`/`staticipdown`, the exit node). Credential-like assignments are
    redacted.
  - Never captured: `~/.claude.json`, logins, history, sessions, caches, plugin data.
- Baseline committed (the real capture of this Mac).
- `tests/cc-capture.bats` (5 tests): sanitize transform, file/skill/plugin/zsh capture, idempotence + `--check`,
  abort-on-secret writes nothing, mirror deletes removed skills but keeps a repo-only `CLAUDE.md`.
- `tests/repo.bats`: the secret scan ignores tracked-but-deleted files (`grep -s`).
- Docs: `config/README.md` (captured file table), `sync-settings.md` (capture behaviour, sanitizing, `--check`),
  `mac-rebuild.md` (new section: restore the baseline by hand until `install.sh mac` exists), `verify.md` rows 1e–1g.

## Verified
- `make capture` → 12 files written; 2nd run → `cc-capture: no changes`; `bin/cc-capture --check` →
  `config/ matches the Mac`, exit 0.
- `jq '[.hooks[][].hooks[] | select(.command | test("afplay"))] | length' config/claude/settings.mac.json` → `4`.
- `settings.mac.json` equals `~/.claude/settings.json` (Mac has no credential env keys or agent-push hooks yet).
- `make lint` → `lint: ok (4 files)`; `make test` → 13/13 ok.
- The manual restore snippet in `mac-rebuild.md` was run twice against a scratch `$HOME` (without npm/plugin
  installs). It deep-merged, backed up, copied all files and was re-runnable.

## Notes / findings
- Not in the plan's facts: `alias cc='claude --continue'` exists (shadows `/usr/bin/cc` in interactive shells). It is
  captured as is.
- Statusline bug confirmed: `statusline-combined.sh` hardcodes node v24.13.0, but nvm has v24.21.0 (default alias
  `24`). It is captured verbatim; Phase 3 fixes it on the Mac, then re-captures.
- No `~/.claude/CLAUDE.md`, `keybindings.json`, `agents/`, `commands/` or `output-styles/` on the Mac, and
  `~/.claude/hooks/` is empty.

## Outstanding (human)
- None for this phase. The `repos.txt` allowlist decision from Phase 0 is still open, and those files are untouched.
