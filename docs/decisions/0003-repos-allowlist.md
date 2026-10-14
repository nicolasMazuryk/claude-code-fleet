# 0003 — Remote Control servers from a versioned allowlist

- Status: accepted (2026-10, confirmed with user)
- Plan: Phases 3 and 4

## Context
The spec starts one RC server for every git repo under `AGENTS_ROOT`. On the Mac that is `~/Documents` with 32 repos:
32 idle Claude Code processes, plus archives and experiments that should not be steerable from the phone.

## Decision
- RC servers run only for repos listed in `config/<host>/repos.txt` (`config/mac/repos.txt`,
  `config/cloud/repos.txt`; one repo directory name per line, `#` comments allowed). The files are versioned here.
- `rc-servers` reconciles: Mac → tmux session `rc`, one window per listed repo (unlisted windows are closed);
  cloud → `systemctl enable --now cc-rc@<repo>` for listed repos, disable units no longer listed.
- `repo-init --rc <repo>` appends to the host's `repos.txt` (then commit the change).
- Agent View `@` dispatch is unaffected: it still sees every repo one level below `AGENTS_ROOT`.

## Consequences
- Adding a repo to the app is a reviewed git change; a rebuild restores exactly the same servers.
- RAM on the A1 VM is bounded by the list, not by what happens to be cloned.
