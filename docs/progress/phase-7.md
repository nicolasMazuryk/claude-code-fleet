# Phase 7 — Hardening and disaster-recovery drills

Date: 2026-10-17 · Branch: `phase-7-doctor` (from `main` 91672cb) · Status: **`cc-doctor`, tests and the Mac dry-run
drill done and merged (PR #2, 28bedc9); `make doctor` green on both hosts. Cloud wipe/restore drill skipped by the
owner's decision; iPhone re-add drill waits for the human.**

## Done
- **`bin/cc-doctor [--local]`** (`make doctor`): read-only, no sudo, never prints the ntfy topic; exit 1 on any FAIL.
  One line per check (`ok | warn | FAIL | skip`), each FAIL names its fix. Areas per host: `tools config runtime rc
  relay ntfy settings tcc disk` (details in the script header and `bin/README.md`). On the Mac it then runs cloud's
  own `cc-doctor --local` over `ssh cloud` and compares cloud's `settings.json` with `cc-sync-settings --print`
  (4 relayed). Repo path from `CC_ORCH_DIR` in the host config. Linked on cloud by `install.sh` (not Mac-only).
  - Full Disk Access is measured, not guessed: `tmux run-shell` asks the launchd-started tmux server to read
    `~/Documents`; plus a fresh `Operation not permitted` in `/tmp/cc-orchestrator-start.log` (newer than the plist).
  - mosh firewall rule = current Cellar `realpath`, via `mac-remote-access status` (the Phase 6 note).
  - cloud repos listed but not trusted (`job-search-pipeline`, `wick-sweep-reclaim-backtester`, by the owner's
    choice) are `skip`, not FAIL.
- **`cc-capture` fix:** `*.bak.*` and `.DS_Store` under `~/.claude` (e.g. `hooks/agent-push.sh.bak.*` left by
  `install.sh`) were about to be captured into `config/`; now dropped (bats test). Capture refreshed: 5 new permission
  allow rules, the local `orchestrate` skill, the new exit-node IP in `zshrc.captured`.
- **Tests:** `tests/cc-doctor.bats` (5: healthy cloud/Mac, and each FAIL class: rc drift, unlisted server, legacy
  unit, topic mode, settings without relays, unlinked script, stale relay copy, lost relay, fresh TCC denial; the
  topic never appears in output). The plan's other test items already existed: `cc-sync-settings` fixture → 4
  relays (`cc-sync-settings.bats`), relay hash rejection (`agent-relay.bats`), push gating table
  (`agent-push.bats`). `make lint test`: lint ok (24 files), 71/71.
- **Live results (2026-10-17, before merge):** Mac `cc-doctor --local` 19 ok; cloud (branch copy piped over ssh)
  17 ok, 2 skip; Mac → cloud settings parity ok.

## Drill: Mac (dry run of `mac-rebuild`), 2026-10-17
- Fresh `gh repo clone` of `main` into a scratch `$HOME/Documents`, `./install.sh mac` with
  `CC_INSTALL_NO_BREW=1 CC_INSTALL_NO_LAUNCHD=1 CC_INSTALL_NO_VAULT=1`: 34 changes (links, config, tmux, claude files,
  baseline restore, settings seed + merge, new 0600 topic, zshrc line, `Host cloud`, cmux, relay copies, both plists);
  second run `install.sh mac: no changes`.
- The rebuilt `~/.claude/settings.json` equals the live one (home path rewritten): orchestrator check
  `true false false mac 2 4`, same env keys; the only difference was the 5 allow rules captured on this branch.
- Restore-baseline snippet: `plugins.json` queries resolve (2 marketplaces, user plugins listed).
- Findings fixed in `mac-rebuild.md`: step 4 still `cd cc-orchestrator` (→ `claude-code-fleet`); step 6
  `rc:cc-orchestrator` (→ `rc:claude-code-fleet`); stale status line. Not exercised (human/GUI): Tailscale login,
  firewall, `/login`, Remote Control acceptance, Full Disk Access, Remote Login; `cc-doctor` checks their results.

## After merge (2026-10-17, from `main` 28bedc9)
- `./install.sh cloud`: `install.sh cloud-local: 2 change(s)` (the new `cc-doctor` link), settings `ok`, `4 macOS-only
  hook handler(s) relayed`; `cc-rc@` running for arbinet, arbinet-specs, offers-pipeline.
- `make doctor` (verify row 10): **`cc-doctor: 37 ok, 0 warn, 0 FAIL, 2 skip`**, exit 0. Mac 18 ok; cloud 19 ok,
  including `settings.json = cc-sync-settings output`; skips are the untrusted-by-choice `job-search-pipeline` and
  `wick-sweep-reclaim-backtester`.

## Not done
- **Cloud drill** (oci `make wipe` → `make restore` → `./install.sh cloud` → `make doctor`): **skipped, owner's
  decision (2026-10-17).** The procedure stays in `cloud-rebuild.md` and oci `wipe-and-restore.md`; the last oci
  wipe/restore drill was 2026-10-13 (before cc-orchestrator took over the cloud runtime).
- **iPhone drill** (human): delete the `cloud` and `mac` hosts in Moshi and re-add them from `iphone-setup.md` alone.

## Closed after the phase
- Push-tap re-check (verify row 7d): re-checked by owner 2026-10-18, passed (the tap opens the Claude app).
