# Phase 3 — Mac runtime

Date: 2026-10-14 · Branch: `phase-3-mac-runtime` (stacked on `phase-2-network`)

## Done
- **Scripts (`bin/`)**:
  - `agent-env`: nvm default alias, `set -u` safe; `CC_ORCH_CONFIG` override for tests.
  - `agents-loop` and `rc-serve`, as the spec.
  - `rc-servers`: reconciles against `$REPOS_FILE`. Exact tmux targets (`=rc`, `=rc:=<repo>`); closes windows of
    repos that are no longer listed.
  - `cc-orchestrator-start`.
  - `repo-init`:
    - `--rc` appends to the allowlist once; `--no-trust` skips the `claude` step
    - a bare name on cloud is cloned from `github.com/nicolasMazuryk`
    - runs `rc-servers` only for listed repos
  - `fleet`: merged table, needs-you first, with `logs|restart|attach <host> <repo>`. Cloud is unreachable today,
    which it reports on stderr.
  - `agent-present`.
- **`hooks/agent-push.sh`**: the spec version. It also exits 0 when no topic exists, and has test hooks
  `AGENT_PRESENT` and `AGENT_PUSH_CURL`.
- **`install.sh mac`** (idempotent; backs up every file before overwriting it), in order:
  - tools (brew)
  - `bin/` symlinks
  - `~/.config/cc-orchestrator/config` and the zshrc snippet link
  - `~/.tmux.conf` and `~/.claude/CLAUDE.md`
  - the statusline fix
  - `~/.claude/hooks/agent-push.sh` (a copy)
  - missing baseline files from `config/claude/` (never overwrites)
  - settings: seeded if absent, then `settings.orchestrator.json` deep-merged and agent-push groups appended to
    `Notification` and `Stop` once; written only on a real change
  - ntfy topic: kept if present, else Vault (best effort via the oci CLI), else a new random one, 0600
  - `~/.zshrc` line, `Host cloud` in `~/.ssh/config`, cmux.json (only over cmux's empty template)
  - LaunchAgent `cc-orchestrator.claude.agents`, re-bootstrapped only when its plist changes
  - `install.sh cloud` exits 2 with "Phase 4".
- **Config**:
  - `config/claude/CLAUDE.md` (global agent rules)
  - `config/mac/{config.tmpl,tmux.conf,zshrc.snippet,ssh_config.snippet,cmux.json}`
  - `config/mac/launchd/*.plist.tmpl`
  - statusline fix in `config/claude/statusline-combined.sh`
  - `.worktreeinclude` in this repo
- **Allowlists** (pending human confirmation; one line each, trivially editable): `config/mac/repos.txt` =
  `cc-orchestrator`, `config/cloud/repos.txt` = `offers-pipeline`.
- **`cc-capture`**: no longer captures `~/.claude/hooks/agent-push.sh`. The baseline was re-captured after install:
  `settings.mac.json` now has the orchestrator keys and still no agent-push handlers.
- **Tests**:
  - `tests/install-mac.bats` (6): merge, hook append once, files, idempotence with no new backups, foreign
    cmux/`Host cloud` kept, invalid JSON aborts, seeding.
  - `tests/agent-push.bats` (8): the gating table.
  - `tests/rc-servers.bats` (4): reconcile with a private tmux socket and a stub `rc-serve`; `repo-init`.
- **Docs**:
  - mac-rebuild (install steps, Remote Control accept via `rc:<repo>`, Full Disk Access check)
  - verify rows 2–2i
  - troubleshooting, add-repo, remove-repo, sync-settings
  - spec §2.2, §2.6, §2.7, §4.4, §4.6
  - bin/ and config/ READMEs

## Verified (live Mac)
- `brew install tmux` → tmux 3.8. mosh 1.4.0, shellcheck and bats were already installed.
- `./install.sh mac`: 22 changes on the first run; a re-run printed `install.sh mac: no changes`.
- Settings diff against the backup `settings.json.bak.20261014-231907` contains only these changes:
  - `remoteControlAtStartup` added (`true`)
  - `agentPushNotifEnabled` and `inputNeededNotifEnabled` flipped `true` → `false`
  - `env.CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX=mac` added
  - one agent-push group appended to `Notification` and one to `Stop`

  The 4 `afplay` hooks and all other keys are unchanged.
- The LaunchAgent is loaded: `program = /opt/homebrew/bin/tmux`, `last exit code = 0`. The tmux sessions `agents`
  (`bash ~/.local/bin/agents-loop` → Agent View listing the Mac sessions) and `rc` (windows `idle` and
  `cc-orchestrator`) are up.
- `rc:cc-orchestrator` waits at `Enable Remote Control? (y/n)`. This is the one-time human acceptance.
- `fleet` lists 5 Mac sessions and prints `fleet: cloud unreachable (ssh cloud)`.
- Other checks:
  - `ssh -G cloud` → `hostname cloud`, `user agent`, ControlMaster auto
  - topic file `-rw-------` in a `drwx------` directory
  - `am` and `ac` aliases resolve in `zsh -i`
  - the statusline exits 0 with a PATH that has no node, and resolves to `~/.nvm/versions/node/v24.21.0/bin/node`
- Worktree + `.env`, the scriptable part, in a scratch repo `/tmp/cc-p3-wt` (removed afterwards):
  - `repo-init --no-trust` wrote `.gitignore` and `.worktreeinclude`
  - `claude -w p3check -p …` created `.claude/worktrees/p3check/` with `.env` copied
- `make capture` updated `settings.mac.json` only; a second run printed `no changes`; `--check` → matches.
- `make lint` → `lint: ok (14 files)`; `make test` → 34/34 ok. Both run under macOS `/bin/bash` 3.2.

## Findings / deviations
- **TCC:** a launchd job whose program is a script in `~/Documents` fails with `bash: …/cc-orchestrator-start:
  Operation not permitted`. The LaunchAgent now execs `/opt/homebrew/bin/tmux new-session -d -s cc-start
  cc-orchestrator-start`, so the scripts run inside the tmux server and only tmux needs access.
  - In this session the launchd-started tmux could already read `~/Documents` without a grant being seen. Whether
    that holds after a reboot or login is unconfirmed, so Full Disk Access for tmux stays a human step.
- The relay LaunchAgent is not installed yet. `bin/agent-relay` is Phase 5, and a KeepAlive job pointing at a
  missing program would crash-loop. `install.sh` installs it automatically once the script exists.
- **Live checkout:** `~/.local/bin/*`, `CC_ORCH_DIR` and the zshrc snippet link currently point at this worktree
  (`.claude/worktrees/impl`), because `main` has no Phase 3 files yet. After merge, re-run `./install.sh mac` from
  `~/Documents/cc-orchestrator`. It relinks everything, and the second run is a no-op.
- **Native push off:** native Claude app pushes are now off (`agentPushNotifEnabled: false`). Until the iPhone
  subscribes to the ntfy topic (Phase 6), away-from-Mac alerts go nowhere.
- `~/.ssh/config` already ended with `Host *` (IdentityFile `~/.ssh/nicolas`). `Host cloud` is appended after it,
  which is fine because `Host *` sets no HostName or User.
- `~/.config/cmux/cmux.json` was cmux's all-comments template. It was replaced by `config/mac/cmux.json`, with a
  backup; the values were checked against the cmux schema.

## Outstanding (human)
1. Accept Remote Control once in `rc:cc-orchestrator`.
2. Confirm the allowlists.
3. Full Disk Access for tmux, checked after the next login.
4. Store the ntfy topic in Vault.
5. Run `@cc-orchestrator hello` in `am`, and check that the app lists `mac/cc-orchestrator`.
6. After merge, re-run `./install.sh mac` from the main checkout.

Exact commands are in the PR body.
