# Phase 0 — Repo foundation and docs skeleton

Date: 2026-10-14 · Branch: `phase-0-foundation`

## Done
- `CLAUDE.md` (agent operating manual: invariants, escalation list, real names, layout, how to change things).
- `README.md` → docs index; `docs/architecture.md`; `docs/spec.md` (prompt.md adapted to real hosts/paths/users,
  incl. allowlist `rc-servers`, nvm `agent-env`, cloud systemd units, sync additions, policy).
- ADRs 0001–0005: Tailscale on OCI, ownership split, repos allowlist, ntfy public topic, capture/apply settings.
- Runbooks: 00-bootstrap-from-zero, mac-rebuild, cloud-rebuild, iphone-setup, add-repo, remove-repo,
  sync-settings, rotate-secrets, upgrade-claude-code, troubleshooting, verify (spec §9 + §10 with real names).
- Skeleton: `bin/`, `hooks/`, `config/{claude,mac,cloud,tailscale,iphone}` (+ `config/README.md` with the phase per
  file), `config/claude/settings.orchestrator.json`, `config/claude/cloud-settings.json`, empty `repos.txt` allowlists.
- `Makefile` (help, install-mac, install-cloud, sync, capture, doctor, fleet, lint, test; unimplemented targets exit 2
  naming the phase), `.gitignore`, `tests/` (shell-files.sh for lint, `repo.bats` structural + secret scan).
- `brew install shellcheck bats-core` on the Mac.
- GitHub remote: `origin` = `git@github.com:nicolasMazuryk/cc-orchestrator.git`, already existed, verified **PRIVATE**.

## Verified
- Facts re-checked: tmux/mosh missing, `/usr/bin/jq`, node v24.21.0 via nvm, claude 2.1.300, 4 hook events
  (Notification, PreToolUse, Stop, StopFailure), plugins warp/claude-hud/claude-md-management, oci bootstrap
  contents (`agent@.service`, `fleet`, settings write).
- `make lint` → `lint: ok (1 files)`; `make test` → 8/8 ok. Negative test: a planted ntfy URL and a broken link
  make tests 7 and 4 fail.
- "Done when": a fresh Explore agent (no prompts/ access) answered "how do I add a repo to cloud?" correctly from
  README → CLAUDE.md → add-repo.md. Its ambiguity notes (which path applies now, deploy-before-merge, sudo, `--rc` on
  cloud, `ac`/`fleet` undefined) were fixed in add-repo.md.

## Outstanding (human)
- Decide the initial allowlists `config/mac/repos.txt` and `config/cloud/repos.txt` (cloud: at least the repos
  currently in `/data/fleet` with `agent@<repo>`, to keep them across the Phase 4 migration).
- Open question for Phase 4: whether `claude remote-control` needs a pty under systemd (`cc-rc@.service` is
  `Type=simple` in the spec; oci ran it inside tmux).
