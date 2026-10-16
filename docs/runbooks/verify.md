# Verify (rollout + spec §10 checks, real names)

Each phase's PR records the output of its rows. `make doctor` (Phase 7) automates most of them.

## Rollout (spec §9)

| # | Area | Command / action | Expected | Phase |
|---|---|---|---|---|
| 1 | Network | Mac: `ssh agent@cloud true; echo $?` · `script -q /dev/null sh -c 'stty rows 40 cols 120; mosh agent@cloud -- sh -c "sleep 2; echo MOSH_OK"'` (no TTY → mosh needs a size, else `Error: vector`; plain `cloud` once Phase 3 writes `~/.ssh/config`) | `0`; `MOSH_OK`. **2026-10-15: PASS** (prints `agent@app`) | 2 |
| 1a | Network | Mac: `tailscale ping --icmp -c 2 cloud` | pong. **2026-10-15: PASS** (100.64.0.10) | 2 |
| 1b | Network | Mac: `ssh agent@cloud 'sudo tailscale ping --icmp -c 2 --timeout 3s macbook'` | no pong (ACL: no `src: tag:cloud`). Plain disco `tailscale ping` may pong: it runs below the ACL. **2026-10-15: PASS** (times out) | 2 |
| 1c | Network | Mac: `cd ~/Documents/oci && make ssh VM=cloud CMD=true` (`VM=app` before 2026-10-16) | Bastion still works. **2026-10-15: PASS** (`scripts/ssh.sh app true`, rc 0) | 2 |
| 1d | Network | Mac: `curl -s https://ifconfig.me`; `tailscale status --self --peers=false` | the `static-ip` address; self is `macbook`. **2026-10-15: PASS** (178.104.255.141, `macbook`) | 2 |
| 1h | Network | Admin console save of `config/tailscale/policy.hujson`; `bats tests/tailscale-policy.bats` | saved (policy `tests` pass); 3/3 ok. **2026-10-15: PASS** (applied by the owner) | 2 |
| 1i | Network | `cd ~/Documents/oci && scripts/ssh.sh cloud 'sudo iptables -S INPUT; sudo grep -c tailscale0 /etc/iptables/rules.v4'`; run `make host-sync VM=cloud` twice | `tailscale0` UDP 60000:61000 ACCEPT before the REJECT; count `1` after both runs. **2026-10-15: PASS** (INPUT rule #7, before REJECT; 2nd host-sync: `tailscale up as cloud.tailnet-example.ts.net.`, no change) | 2 |
| 1j | Network | `/usr/libexec/ApplicationFirewall/socketfilterfw --listapps \| grep -A1 mosh` | `mosh-client`, `mosh-server` at the current `realpath /opt/homebrew/bin/mosh-*`, "Allow incoming connections" | 2 |
| 1k | Rename | `cd ~/Documents/oci && make plan-all`; `make ssh VM=cloud CMD=hostname`; `ssh agent@cloud 'hostname; cat /etc/cloud/cloud.cfg.d/99-zz-core-hostname.cfg; grep 127.0.1.1 /etc/hosts'` | `no changes` ×3; `cloud`; `cloud`, `hostname: cloud`, `127.0.1.1 cloud cloud`. After an approved `sudo reboot`, still `cloud` | 4a |
| 1l | Rename | `curl -sI https://mazuryktech.com \| head -1`; `curl -s -o /dev/null -w '%{http_code}' https://status.mazuryktech.com/status/core`; `ssh agent@cloud 'systemctl is-active cc-rc@offers-pipeline'` (`agent@…` before Phase 4b) | `HTTP/2 200`; `200`; `active` (the OCI console shows `core-vm-cloud`, `core-alarm-cloud-*`; Kuma shows `core-vm-cloud origin :443 (private)`) | 4a |
| 1m | Rename | Mac: `scutil --get ComputerName; scutil --get LocalHostName; scutil --get HostName; hostname` | `nicolas-macbook` ×4 | 4a |
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
| 3 | Cloud | `make sync` (= `bin/cc-sync-settings`) | `4 macOS-only hook handler(s) relayed`; 2nd run `settings ok`, `files ok`. **2026-10-16: PASS** | 4 |
| 3a | Cloud | `./install.sh cloud --dry-run`; `./install.sh cloud` twice | dry run lists `would …` and writes nothing; 2nd real run `install.sh cloud-local: no changes`, `Mac side: 0 change(s)`. **2026-10-16: PASS** | 4b |
| 3b | Cloud | `ac`, then `@<repo> hello` (scriptable part: `ssh cloud 'cd /data/fleet/<repo> && claude --bg -w t "say hello"'`, then `claude agents --json`, `claude rm <id>`) | worktree under `/data/fleet/<repo>/.claude/worktrees/` (with `.env` if the repo has one). **2026-10-16: scriptable part PASS** (`offers-pipeline/.claude/worktrees/p4b-hello`, "hello from cloud"); `ac` needs the `/data/fleet` trust prompt accepted once | 4 |
| 3c | Cloud | `ssh cloud 'systemctl list-units "cc-rc@*" "agent@*" --all --no-legend'` | one active `cc-rc@` per trusted repo in `config/cloud/repos.txt`; no `agent@*`. **2026-10-16:** `cc-rc@offers-pipeline` only (other 4 wait for trust) | 4 |
| 3d | Cloud | `[H]` `ssh cloud 'sudo reboot'`, then `ssh cloud 'systemctl is-active cc-agents; systemctl list-units "cc-rc@*" --no-legend; tmux ls'`; `fleet` | everything back | 4 |
| 3e | Cloud | `fleet` (Mac) | `mac` and `cloud` rows (cloud rows need a cloud session); no `cloud unreachable`. **2026-10-16: PASS** | 4 |
| 3f | Cloud | `journalctl -u cc-rc@<repo> -n 20` on cloud | `✔ Ready · <repo>`, `--name cloud/<repo>`, no tmux in the cgroup. **2026-10-16: PASS** | 4b |
| 3g | Cloud | `cd ~/Documents/oci && make host-sync VM=cloud` after `install.sh cloud`; compare `systemctl show cc-rc@<repo> cc-agents -p MainPID -p NRestarts -p ActiveEnterTimestamp` before/after | identical (host-sync never touches `cc-*`); 2nd host-sync logs no `legacy:` lines. **2026-10-16: PASS** | 4b |
| 3h | Cloud | `ssh cloud 'ls /etc/systemd/system /usr/local/bin; sudo ls /opt/core; ls /etc/rsyslog.d'` | no `agent@.service`, `fleet`, `30-core-agent.conf`; `cc-agents.service`, `cc-rc@.service`, `30-cc-orchestrator.conf` present. **2026-10-16: PASS** | 4b |
| 4 | Sounds | cloud session asks a question | Choo Choo on the Mac | 5 |
| 4b | Sounds | change a Mac sound hook, trigger on cloud | skipped + logged in `/tmp/agent-relay.log` | 5 |
| 5 | Pushes | lock the Mac; trigger on both hosts | ntfy push within 30 s from both | 5 |
| 5b | Pushes | unlocked + moving the mouse | no pushes | 5 |
| 6 | Remote Control | Claude app → Code | `mac/<repo>` (Phase 3) and `cloud/<repo>` under device `cloud` (Phase 4); new session lands in a worktree; approve a prompt from the app | 3–4 |
| 7 | iPhone | Moshi `cloud` and `mac` | dispatch, peek-reply, attach-approve on both; tapping a push opens the session | 6 |
| 8 | Docs | a fresh agent answers "how do I add a repo to cloud?" from docs alone | → [add-repo](add-repo.md) | 0 |
| 9 | Repo | `make lint test` | passes | 0+ |

## Check once (spec §10)

| # | Question | How | Finding |
|---|---|---|---|
| 1 | Do Agent View background sessions appear in the app with `remoteControlAtStartup`? | dispatch, look in the app | _tbd_ |
| 2 | How does the app start a session on `cloud/<repo>`; does it land in its own worktree? | start one | _tbd_ |
| 3 | Is `CLAUDE_JOB_DIR` passed to hooks of background sessions? | log `env` once from `agent-push.sh` | _tbd (Phase 5)_ |
| 4 | Does `cc-sync-settings` count all 4 Choo Choo handlers; relayed sound identical? | `make sync` | 4 counted (2026-10-16); sound identity: Phase 5 |
| 5 | Does `@` list every repo in `AGENTS_ROOT`? (names have no spaces; check `FIO`, `fio.contracts`) | type `@` | _tbd_ |
| 6 | `claude` from an SSH login on the Mac: Keychain login available? | mosh macbook → `claude` | _tbd (Phase 6)_ |
| 7 | Tenancy A1 allowance | oci `make free-tier` | 4 OCPU / 24 GB, using 2 / 12 |
