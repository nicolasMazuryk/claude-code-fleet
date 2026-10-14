# 0002 — Ownership split between `oci` and `cc-orchestrator`

- Status: accepted (2026-10, confirmed with user)
- Plan: Phases 2 and 4

## Context
`~/Documents/oci` (`host/app/bootstrap.sh`) currently installs Claude Code, an `agent@<repo>.service` (tmux +
`claude remote-control --spawn worktree`), a `/usr/local/bin/fleet` CLI, and writes `~agent/.claude/settings.json`.
Two repos configuring Claude Code would drift.

## Decision
- **oci owns the machine:** VM, `/data` volume, packages (incl. tmux, mosh, tailscale), Node, the `agent` user and
  linger, Tailscale enrolment, the mosh iptables rule, gh auth from Vault, all Vault secrets.
- **cc-orchestrator owns everything Claude Code:** scripts (`bin/`), Agent View, RC servers, hooks, settings and their
  sync, and the cloud systemd units `cc-agents.service` / `cc-rc@.service`.
- `agent@.service`, `/usr/local/bin/fleet` and the `settings.json` write are removed from the oci bootstrap (Phase 4,
  via an oci PR). Recommended: the Claude Code binary install moves here too, for a single owner.
- oci docs (`fleet-repos.md`, `access-ssh.md`, `CLAUDE.md`) point to this repo for Claude Code.

## Consequences
- A cloud rebuild is: oci `make restore` (machine) → `./install.sh cloud` from this repo (Claude Code).
- oci verbs `fleet add|rm|ls|attach|logs|restart` are replaced by `repo-init`/`remove-repo` runbook and
  `fleet logs|restart|attach <host> <repo>`.
- Migration must stop/disable `agent@*` before enabling `cc-rc@*` so one repo never has two RC servers.
