# Verify (rollout + spec §10 checks, real names)

Each phase's PR records the output of its rows. `make doctor` (Phase 7) automates most of them.

## Rollout (spec §9)

| # | Area | Command / action | Expected | Phase |
|---|---|---|---|---|
| 1 | Network | Mac: `ssh cloud true; echo $?` · `mosh cloud -- true` | `0`; mosh connects | 2 |
| 1b | Network | cloud: `tailscale ping -c 2 macbook` | fails (ACL: no `src: tag:cloud`) | 2 |
| 1c | Network | Mac: `cd ~/Documents/oci && make ssh VM=app CMD=true` | Bastion still works | 2 |
| 1d | Network | Mac: exit node `static-ip` usable | unchanged | 2 |
| 2 | Mac | `am` | Agent View in tmux `agents` | 3 |
| 2b | Mac | `@<repo> hello` in Agent View | worktree `~/Documents/<repo>/.claude/worktrees/…` with `.env` | 3 |
| 2c | Mac | `tmux list-windows -t rc -F '#W'` | `idle` + exactly the repos in `config/mac/repos.txt` | 3 |
| 2d | Mac | `fleet` | Mac sessions listed | 3 |
| 3 | Cloud | `make sync` | `4 macOS-only hook handler(s) relayed` | 4 |
| 3b | Cloud | `ac`, then `@<repo> hello` | worktree under `/data/fleet/<repo>/.claude/worktrees/` with `.env` | 4 |
| 3c | Cloud | `ssh cloud 'systemctl list-units "cc-rc@*" --no-legend'` | one active unit per line of `config/cloud/repos.txt`; no `agent@*` | 4 |
| 3d | Cloud | `ssh cloud 'sudo reboot'`, then `fleet` | everything back | 4 |
| 4 | Sounds | cloud session asks a question | Choo Choo on the Mac | 5 |
| 4b | Sounds | change a Mac sound hook, trigger on cloud | skipped + logged in `/tmp/agent-relay.log` | 5 |
| 5 | Pushes | lock the Mac; trigger on both hosts | ntfy push within 30 s from both | 5 |
| 5b | Pushes | unlocked + moving the mouse | no pushes | 5 |
| 6 | Remote Control | Claude app → Code | `mac/<repo>` and `cloud/<repo>`; new session lands in a worktree; approve a prompt from the app | 3–4 |
| 7 | iPhone | Moshi `cloud` and `mac` | dispatch, peek-reply, attach-approve on both; tapping a push opens the session | 6 |
| 8 | Docs | a fresh agent answers "how do I add a repo to cloud?" from docs alone | → [add-repo](add-repo.md) | 0 |
| 9 | Repo | `make lint test` | passes | 0+ |

## Check once (spec §10)

| # | Question | How | Finding |
|---|---|---|---|
| 1 | Do Agent View background sessions appear in the app with `remoteControlAtStartup`? | dispatch, look in the app | _tbd_ |
| 2 | How does the app start a session on `cloud/<repo>`; does it land in its own worktree? | start one | _tbd_ |
| 3 | Is `CLAUDE_JOB_DIR` passed to hooks of background sessions? | log `env` once from `agent-push.sh` | _tbd (Phase 5)_ |
| 4 | Does `cc-sync-settings` count all 4 Choo Choo handlers; relayed sound identical? | `make sync` | _tbd (Phase 4)_ |
| 5 | Does `@` list every repo in `AGENTS_ROOT`? (names have no spaces; check `FIO`, `fio.contracts`) | type `@` | _tbd_ |
| 6 | `claude` from an SSH login on the Mac: Keychain login available? | mosh macbook → `claude` | _tbd (Phase 6)_ |
| 7 | Tenancy A1 allowance | oci `make free-tier` | 4 OCPU / 24 GB, using 2 / 12 |
