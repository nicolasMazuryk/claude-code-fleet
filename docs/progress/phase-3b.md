# Phase 3b — Mac runtime: finish and verify

Date: 2026-10-15 · Branch: `phase-3b-finish` (from `main` after PRs #1–#4) · Phases 0–3 and oci-infra#1 merged, host-synced.

## Done
- **Allowlists (owner's final decision)**:
  - `config/mac/repos.txt`: `cc-orchestrator`, `oci`, `claude-power-user`, `arbinet-specs`, `arbinet`
  - `config/cloud/repos.txt`: `offers-pipeline`, `job-hunt`, `wick-sweep-reclaim`, `arbinet-specs`, `arbinet`
    (Phase 4 clones them)
- **Tailscale join credential**: the Vault secret is now a non-expiring OAuth client secret, never rotated. Documented
  in tailscale.md §2, rotate-secrets, cloud-rebuild and ADR 0001.
- **macOS firewall**: allow `mosh-client` and `mosh-server`, documented in mac-rebuild step 2a and verify row 1j.
  `brew upgrade` changes the Cellar path, so the rule must be re-added after an upgrade (troubleshooting row;
  cc-doctor check in Phase 7).
- **mosh without a TTY**: it fails with `Error: vector`. The `script` + `stty` wrapper is now in verify row 1,
  tailscale.md §5 and troubleshooting.
- **Remote Control acceptance**: one global acceptance. `y` sets `remoteDialogSeen: true` in `~/.claude.json`
  (read from the 2.1.300 CLI). Windows that were already waiting at the prompt must be restarted. Documented in
  mac-rebuild step 6 and troubleshooting.
- **Phase 2 results**: filled into `docs/progress/phase-2.md` and verify rows 1–1j.

## Verified (before merge)
- Phase 2, re-run live on 2026-10-15 from the Mac:
  - `ssh agent@cloud` → `agent@app`
  - mosh → `MOSH_OK`
  - `tailscale ping --icmp cloud` → `pong from cloud (100.64.0.10) via ICMP in 44ms`
  - cloud → `macbook` ICMP: `timed out`, `no reply`
  - `ifconfig.me` → `178.104.255.141`; self = `macbook`
  - VM INPUT: line 8 is the `tailscale0` 60000:61000 ACCEPT, line 9 the REJECT; `rules.v4` count `1`
  - Bastion `make ssh VM=app CMD=true` → rc 0
- `make lint` → `lint: ok (14 files)`; `make test` → 34/34 ok.

## Findings
- `claude-power-user` has **no commits** (unborn `HEAD`, everything untracked). `rc-serve --spawn worktree` cannot
  create worktrees there until it has an initial commit.
- `oci` is skipped by `repo-init`. Its `.gitignore` already has `.claude/worktrees/`, it has no `.env`, and its
  `CLAUDE.md` forbids edits to its main checkout, so a `.worktreeinclude` would need an oci PR for no gain.
- `claude-power-user` and `arbinet` have no workspace trust yet (`hasTrustDialogAccepted`). The other three do.
- The oci repo's own `docs/runbooks/secrets-rotation.md` may still describe the 90-day auth key. That fix belongs to an
  oci PR (not done here).

Post-merge results (install from the main checkout, `rc` windows, repo-init) are in the PR conversation and the
follow-up commit below.
