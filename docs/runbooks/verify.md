# Verify (rollout + spec §10 checks, real names)

Each phase's PR records the output of its rows. `make doctor` (Phase 7) automates most of them.

## Rollout (spec §9)

| # | Area | Command / action | Expected | Phase |
|---|---|---|---|---|
| 1 | Network | Mac: `ssh agent@cloud true; echo $?` · `mosh agent@cloud -- true` (plain `cloud` once Phase 3 writes `~/.ssh/config`) | `0`; mosh connects | 2 |
| 1a | Network | Mac: `tailscale ping --icmp -c 2 cloud` | pong | 2 |
| 1b | Network | Mac: `ssh agent@cloud 'sudo tailscale ping --icmp -c 2 --timeout 3s macbook'` | no pong (ACL: no `src: tag:cloud`). Plain disco `tailscale ping` may pong: it runs below the ACL | 2 |
| 1c | Network | Mac: `cd ~/Documents/oci && make ssh VM=app CMD=true` | Bastion still works | 2 |
| 1d | Network | Mac: `curl -s https://ifconfig.me`; `tailscale status --self --peers=false` | the `static-ip` address; self is `macbook` | 2 |
| 1h | Network | Admin console save of `config/tailscale/policy.hujson`; `bats tests/tailscale-policy.bats` | saved (policy `tests` pass); 3/3 ok | 2 |
| 1i | Network | `cd ~/Documents/oci && scripts/ssh.sh app 'sudo iptables -S INPUT; sudo grep -c tailscale0 /etc/iptables/rules.v4'`; run `make host-sync VM=app` twice | `tailscale0` UDP 60000:61000 ACCEPT before the REJECT; count `1` after both runs | 2 |
| 1e | Capture | `make capture`, then `make capture` again | 2nd run: `cc-capture: no changes` | 1 |
| 1f | Capture | `bin/cc-capture --check; echo $?` | `config/ matches the Mac`, `0` | 1 |
| 1g | Capture | `jq '[.hooks[][].hooks[] \| select(.command \| test("afplay"))] \| length' config/claude/settings.mac.json` | `4` | 1 |
| 2 | Mac | `am` (new shell, or `. ~/.zshrc`) | Agent View in tmux `agents`, started from `~/Documents` | 3 |
| 2a | Mac | `./install.sh mac`, then again | 2nd run: `install.sh mac: no changes`; no new `*.bak.*` files | 3 |
| 2b | Mac | `@<repo> hello` in Agent View (scriptable part: `cd <repo> && claude -w t -p ok`, then `ls .claude/worktrees/t/.env`) | worktree `~/Documents/<repo>/.claude/worktrees/…` with `.env` | 3 |
| 2c | Mac | `tmux list-windows -t rc -F '#W'` | `idle` + exactly the repos in `config/mac/repos.txt` | 3 |
| 2d | Mac | `fleet` | Mac sessions listed (`cloud unreachable` on stderr until Phase 4) | 3 |
| 2e | Mac | `launchctl print gui/$(id -u)/cc-orchestrator.claude.agents \| grep -E 'state\|last exit'`; `cat /tmp/cc-orchestrator-start.log` | loaded, `last exit code = 0`; no `Operation not permitted` (else: Full Disk Access for tmux) | 3 |
| 2f | Mac | `jq '{remoteControlAtStartup, inputNeededNotifEnabled, agentPushNotifEnabled, p: .env.CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX, push: [.hooks[][].hooks[] \| select(.command \| test("agent-push"))] \| length, afplay: [.hooks[][].hooks[] \| select(.command \| test("afplay"))] \| length}' ~/.claude/settings.json` | `true`, `false`, `false`, `mac`, `2`, `4` | 3 |
| 2g | Mac | `ssh -G cloud \| grep -E '^(hostname\|user) '`; `stat -f %Lp ~/.config/agent-push/topic` | `hostname cloud`, `user agent`; `600` | 3 |
| 2h | Mac | `tmux capture-pane -p -t rc:<repo> \| tail -3`, after accepting Remote Control once | server running, no `Enable Remote Control? (y/n)` prompt | 3 |
| 2i | Mac | `bin/cc-capture --check` | `config/ matches the Mac` (agent-push hooks and `~/.claude/hooks/agent-push.sh` excluded) | 3 |
| 3 | Cloud | `make sync` | `4 macOS-only hook handler(s) relayed` | 4 |
| 3b | Cloud | `ac`, then `@<repo> hello` | worktree under `/data/fleet/<repo>/.claude/worktrees/` with `.env` | 4 |
| 3c | Cloud | `ssh cloud 'systemctl list-units "cc-rc@*" --no-legend'` | one active unit per line of `config/cloud/repos.txt`; no `agent@*` | 4 |
| 3d | Cloud | `ssh cloud 'sudo reboot'`, then `fleet` | everything back | 4 |
| 4 | Sounds | cloud session asks a question | Choo Choo on the Mac | 5 |
| 4b | Sounds | change a Mac sound hook, trigger on cloud | skipped + logged in `/tmp/agent-relay.log` | 5 |
| 5 | Pushes | lock the Mac; trigger on both hosts | ntfy push within 30 s from both | 5 |
| 5b | Pushes | unlocked + moving the mouse | no pushes | 5 |
| 6 | Remote Control | Claude app → Code | `mac/<repo>` (Phase 3) and `cloud/<repo>` (Phase 4); new session lands in a worktree; approve a prompt from the app | 3–4 |
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
