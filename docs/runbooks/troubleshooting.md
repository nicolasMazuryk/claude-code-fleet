# Troubleshooting

| Symptom | Check / fix |
|---|---|
| `ssh cloud` hangs / denied | Before Phase 3 there is no `Host cloud` entry: use `ssh agent@cloud`. Does `tailscale status` on the Mac show `cloud`? Does the policy ssh rule have users `agent`,`ubuntu`? On the VM (break-glass `cd ~/Documents/oci && make ssh VM=app`): `tailscale status`, `grep -i tailscale /var/log/core-bootstrap.log`. See [tailscale](tailscale.md) |
| Cloud joined as `cloud-1` | A stale `cloud` machine exists (e.g. after `BACKUP=none`). Delete it in the admin console, rename the new one `cloud` |
| Exit node stopped working after a policy change | The policy lost `autogroup:internet:*` for members. Re-apply `config/tailscale/policy.hujson` |
| `mosh cloud` "Nothing received from server" | iptables rule on `tailscale0` for UDP 60000:61000 missing (oci bootstrap). `sudo iptables -S INPUT \| grep 60000` on cloud |
| launchd-started tmux/claude can't read `~/Documents` ("Operation not permitted") | Full Disk Access for `/opt/homebrew/bin/tmux` (and `sshd-keygen-wrapper`, `mosh-server` for phone access) |
| Agent can't find node/pnpm | started without `agent-env`. Dispatch via Agent View / app; on Mac check nvm default alias exists |
| Statusline shows errors | node path hardcoded to a removed version; fixed by `install.sh mac` (Phase 3) |
| No cloud sounds | `/tmp/agent-relay.log` says "skipped": run `make sync`. Relay not running: `launchctl print gui/$(id -u)/cc-orchestrator.claude.relay` |
| `cc-sync-settings` relays < 4 | a sound hook changed; see [sync-settings](sync-settings.md) |
| Too many / no pushes | `agent-present; echo $?` on the Mac (0 = present). Cloud: `ls -l ~/.local/state/agent-events/mac-present` age < 90 s |
| Repo missing in the Claude app | not in `config/<host>/repos.txt`, or server down: Mac `tmux list-windows -t rc`, cloud `systemctl status cc-rc@<repo>` |
| "Workspace not trusted" | `repo-init <repo>` again (TTY) and accept |
| Remote Control disabled | needs claude.ai login; `ANTHROPIC_API_KEY`, custom `ANTHROPIC_BASE_URL` or `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` turn it off |
| Disk filling | `du -sh /data/fleet/*/.claude/worktrees`, `df -h /data`; delete finished sessions (Ctrl+X twice) |

More: original spec §8 (`prompts/prompt.md`) and oci `docs/runbooks/troubleshooting.md` for VM-level issues.
