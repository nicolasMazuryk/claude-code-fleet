# CLAUDE.md: operating manual for this repo

cc-orchestrator is the **single source of truth** for running Claude Code across three devices:
the MacBook (`macbook`), the OCI VM `core-vm-cloud` (Tailscale name and OS hostname `cloud`) and the iPhone.
Rebuilding any of them must be "follow this repo".

- Human entry point: `README.md` → `docs/`.
- Design: `docs/architecture.md`, `docs/spec.md` (the adapted spec), `docs/decisions/` (ADRs).
- Procedures: `docs/runbooks/` (start at `00-bootstrap-from-zero.md`; checks in `verify.md`).
- Implementation plan and phase status: `prompts/plan.md`, `docs/progress/phase-N.md`.
- `prompts/prompt.md` is the original generic spec. It is **historical input**: never edit it, never follow its
  paths (`~/Projects`, `~/src`, user `ubuntu`, fnm) literally. `docs/spec.md` wins where they differ.

## Invariants: do not break these

1. **Secrets never enter git.** Not the ntfy topic, Tailscale auth keys, claude.ai logins, the GitHub PAT, tokens in
   `settings.json` (`env.*TOKEN*`, `*KEY*`), or `~/.claude.json`. Secrets live in OCI Vault (managed from
   `~/Documents/oci-free-tier-platform`: `make secret-put`) or in local files outside the repo (`~/.config/agent-push/topic`).
   `cc-capture` sanitizes before writing to `config/`; `make test` greps for secret-looking strings.
2. **The Mac is the source of truth for Claude Code settings.** Flow is Mac → `config/claude/` (capture) →
   Mac (apply) and Mac → cloud (`cc-sync-settings`). Never edit cloud's `~/.claude` by hand; never sync cloud → Mac.
3. **Cloud is reachable only via Tailscale (`cloud`, `tag:cloud`) or OCI Bastion (break-glass, `make ssh VM=cloud` in
   `~/Documents/oci-free-tier-platform`).** No public IP, no `0.0.0.0/0` ingress, no port 22 on the internet. mosh is allowed only on
   `tailscale0` (UDP 60000–61000).
4. **Cloud must never reach the Mac or the iPhone.** The tailnet policy has no rule with `src: tag:cloud`. Never put a
   Mac key, Mac credential or Mac address that grants access on cloud. Every Mac↔cloud connection (relay, presence,
   sync, fleet) is opened **by the Mac**.
5. **Every script is idempotent.** `install.sh`, `repo-init`, `rc-servers`, `cc-sync-settings` and the oci bootstrap
   are re-run routinely; a second run must change nothing and break nothing.
6. **Every change updates its runbook and `docs/runbooks/verify.md`.** If you change how something is installed,
   started or checked, the matching runbook and the verify steps change in the same commit.
7. **Back up before touching user state.** `~/.claude/settings.json`, `~/.ssh/config`, `~/.zshrc` and LaunchAgents are
   backed up (`*.bak.<timestamp>`) before any write. `~/.claude/settings.json` is deep-merged, never replaced.
8. **Ownership split (ADR 0002).** `~/Documents/oci-free-tier-platform` owns the VM, disk, packages, the `agent` user, Tailscale, the
   mosh iptables rule and Vault secrets. This repo owns everything Claude Code (scripts, Agent View, Remote Control
   servers, hooks, settings sync, cloud systemd units). Changes to oci go through **that repo's** `CLAUDE.md` rules
   (its own branch/worktree + PR); never edit its main checkout directly.

## Escalate to the human (do not do these yourself)

- GUI/admin consoles (Tailscale admin, claude.ai, macOS System Settings / Full Disk Access, iPhone).
- Interactive logins (`claude auth login`, accepting Remote Control, workspace trust prompts), `sudo` that prompts.
- Creating or storing real secrets (Tailscale auth keys, `make secret-put`).
- Shared infra that is hard to reverse: `make wipe`/`restore`, terraform apply/destroy, `make host-sync` against the
  live VM, changing the live tailnet policy, deleting repos/worktrees/user data.
Prepare the exact commands, make them resumable, and list them for the human.

## Real names (do not guess others)

| Thing | Mac | Cloud |
|---|---|---|
| Host / Tailscale name | `macbook` (tailnet `tailnet-example`; was `nicolas-macbook`) | `cloud` = `core-vm-cloud`, `tag:cloud` |
| OS hostname (= Remote Control device name) | `nicolas-macbook` (ComputerName/LocalHostName/HostName) | `cloud` (pinned by the oci bootstrap; was `app`) |
| User / home | `nicolas`, `/Users/nicolas` | `agent`, `/data/home/agent` (on persistent `/data`) |
| `AGENTS_ROOT` | `~/Documents` | `/data/fleet` |
| Agent View tmux session | `agents` | `fleet` |
| RC servers | tmux session `rc`, one window per repo | systemd `cc-rc@<repo>`, headless (no tmux); oci `agent@<repo>` removed in Phase 4b |
| RC allowlist | `config/mac/repos.txt` | `config/cloud/repos.txt` |
| Node | nvm (`~/.nvm`), pnpm via corepack | system Node 24 (NodeSource), pnpm via corepack |
| Starts at boot | LaunchAgents `cc-orchestrator.claude.{agents,relay}` | `cc-agents.service`, `cc-rc@.service` (linger on) |
| Claude Code binary | native installer (`~/.local/bin/claude`) | same, installed by `install.sh cloud` (not oci) |
| This repo on the host | `~/Documents/claude-code-fleet` (live checkout) | `~/claude-code-fleet`, an rsync copy (never edit it there) |

Environment notes: macOS ships bash 3.2 and BSD tools. Scripts use `#!/usr/bin/env bash`, avoid bash-4-only features
unless the script only runs on cloud, and avoid `${arr[@]}` on empty arrays under `set -u`
(use `${arr[@]+"${arr[@]}"}`). `jq` on the Mac is `/usr/bin/jq`. The `!` shell in Claude Code has no TTY.

## Layout

```
bin/        scripts, symlinked into ~/.local/bin on both hosts (editing the repo changes what runs)
hooks/      Claude Code hook scripts (agent-push.sh)
config/     claude/ (captured + enforced settings), mac/, cloud/, tailscale/, iphone/
docs/       architecture, spec, decisions/ (ADRs), runbooks/, progress/
tests/      shellcheck + bats
install.sh  ./install.sh mac | cloud (idempotent)
Makefile    make help
```

`~/.claude` uses **capture/apply, not symlinks**: Claude Code rewrites `settings.json` atomically, which breaks
symlinks. `cc-capture` snapshots Mac → `config/claude/` (sanitized); `install.sh mac` applies it back.

## How to change things

1. Read the matching runbook and ADR first. If a change contradicts an ADR, write a new ADR that supersedes it.
2. Branch (`phase-N-*` or `feat/*`), commit with the trailer
   `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, open a **draft** PR into `main`.
   Never push to `main`, never force-push, never merge.
3. Run `make lint test` before committing. Add a bats test for any non-trivial transform (settings sync,
   relay hash check, push gating).
4. Update the runbook + `verify.md`, and the phase log in `docs/progress/` when working a plan phase.
