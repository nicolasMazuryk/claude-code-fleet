# Troubleshooting

| Symptom | Check / fix |
|---|---|
| `ssh cloud` hangs / denied | Before Phase 3 there is no `Host cloud` entry: use `ssh agent@cloud`. Does `tailscale status` on the Mac show `cloud`? Does the policy ssh rule have users `agent`,`ubuntu`? On the VM (break-glass `cd ~/Documents/oci && make ssh VM=app`): `tailscale status`, `grep -i tailscale /var/log/core-bootstrap.log`. See [tailscale](tailscale.md) |
| Cloud joined as `cloud-1` | A stale `cloud` machine exists (e.g. after `BACKUP=none`). Delete it in the admin console, rename the new one `cloud` |
| Exit node stopped working after a policy change | The policy lost `autogroup:internet:*` for members. Re-apply `config/tailscale/policy.hujson` |
| `mosh cloud` "Nothing received from server" | iptables rule on `tailscale0` for UDP 60000:61000 missing (oci bootstrap). `sudo iptables -S INPUT \| grep 60000` on cloud |
| `mosh cloud` hangs / "Nothing received" only from the Mac, after a `brew upgrade` | the Application Firewall rule is on the old Cellar path: `socketfilterfw --listapps \| grep -A1 mosh` vs `realpath /opt/homebrew/bin/mosh-client`; re-add ([mac-rebuild](mac-rebuild.md) step 2a) |
| `mosh` prints `Error: vector` (scripts, `!` shell, no TTY) | mosh-client needs a terminal size: `script -q /dev/null sh -c 'stty rows 40 cols 120; mosh cloud -- true'` |
| launchd-started tmux/claude can't read `~/Documents` ("Operation not permitted" in `/tmp/cc-orchestrator-start.log`) | Full Disk Access for `$(realpath /opt/homebrew/bin/tmux)` (and `sshd-keygen-wrapper`, `mosh-server` for phone access). The LaunchAgent must exec tmux, not a script in `~/Documents`: re-run `./install.sh mac` |
| No `agents`/`rc` tmux sessions after login | `launchctl print gui/$(id -u)/cc-orchestrator.claude.agents`; `cat /tmp/cc-orchestrator-start.log`; start by hand: `cc-orchestrator-start` |
| `rc:<repo>` window shows `Enable Remote Control? (y/n)` | Not accepted yet, or the window started before the (global) acceptance: `jq .remoteDialogSeen ~/.claude.json`. `null` → `tmux attach -t rc:<repo>` → `y` → `Ctrl-b d`. `true` → `tmux kill-window -t rc:<repo> && rc-servers` |
| `am`/`ac` not found | new shell, or `. ~/.zshrc`; check `~/.config/cc-orchestrator/zshrc.snippet` links into this repo (`./install.sh mac`) |
| `~/.local/bin/*` point into a deleted worktree | re-run `./install.sh mac` from `~/Documents/cc-orchestrator` (relinks bin/, rewrites `CC_ORCH_DIR`) |
| Agent can't find node/pnpm | started without `agent-env`. Dispatch via Agent View / app; on Mac check nvm default alias exists |
| Statusline shows errors / claude-hud half blank | `echo '{}' \| ~/.claude/statusline-combined.sh`; it needs `node` on PATH or an nvm version matching `~/.nvm/alias/default`; `npm i -g ccstatusline` under that node |
| No cloud sounds | `/tmp/agent-relay.log` says "skipped": run `make sync`. Relay not running: `launchctl print gui/$(id -u)/cc-orchestrator.claude.relay` |
| `cc-sync-settings` relays < 4 | a sound hook changed; see [sync-settings](sync-settings.md) |
| Too many / no pushes | `agent-present; echo $?` on the Mac (0 = present). Cloud: `ls -l ~/.local/state/agent-events/mac-present` age < 90 s |
| Repo missing in the Claude app | not in `config/<host>/repos.txt`, or server down: Mac `tmux list-windows -t rc`, cloud `systemctl status cc-rc@<repo>` |
| "Workspace not trusted" | `repo-init <repo>` again (TTY) and accept |
| Remote Control disabled | needs claude.ai login; `ANTHROPIC_API_KEY`, custom `ANTHROPIC_BASE_URL` or `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` turn it off |
| Disk filling | `du -sh /data/fleet/*/.claude/worktrees`, `df -h /data`; delete finished sessions (Ctrl+X twice) |

More: original spec §8 (`prompts/prompt.md`) and oci `docs/runbooks/troubleshooting.md` for VM-level issues.
