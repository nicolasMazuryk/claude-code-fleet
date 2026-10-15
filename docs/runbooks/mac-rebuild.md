# Rebuild the Mac

Status: steps 1–8 runnable (Phase 3). Phone access (step 9) is Phase 6. `[H]` = human-only.

## Facts
- User `nicolas`; repos in `~/Documents`; node via nvm (`~/.nvm`, default alias v24.x), pnpm via corepack.
- `jq` is `/usr/bin/jq`; gh, rsync in `/opt/homebrew/bin`; cmux and Ghostty installed.
- Tailscale node name **`macbook`** (tailnet `tailnet-example`; was `nicolas-macbook-pro`). Exit node `static-ip` must keep working.

## Steps
1. Homebrew; `brew install tmux mosh shellcheck bats-core gh rsync` (mosh installed in Phase 2); install cmux + Ghostty; nvm + `nvm install 24 && nvm alias default 24 && corepack enable`.
2. `[H]` Tailscale app, log in, rename the machine to `macbook`: admin console → machine → Edit machine name (turn
   off auto-generate); `tailscale set --hostname=macbook` only works if it was never renamed in the console. Re-select the
   exit node `static-ip` if needed. Details: [tailscale](tailscale.md) §4.
3. Claude Code: `curl -fsSL https://claude.ai/install.sh | bash`; `[H]` `claude` → `/login`.
4. `cd ~/Documents && gh repo clone nicolasMazuryk/cc-orchestrator && cd cc-orchestrator`.
5. `./install.sh mac` (idempotent; run it from the checkout that should be live, normally
   `~/Documents/cc-orchestrator` on `main`; re-run any time, a second run prints `install.sh mac: no changes`).
   What it does, in order (every overwritten file is backed up first as `<file>.bak.<timestamp>`):
   - `brew install tmux mosh` if missing;
   - symlinks `bin/*` → `~/.local/bin/` (and drops links to scripts that no longer exist);
   - writes `~/.config/cc-orchestrator/config` from `config/mac/config.tmpl` (`CC_ORCH_DIR` = this checkout) and
     links `~/.config/cc-orchestrator/zshrc.snippet` → `config/mac/zshrc.snippet`;
   - `~/.tmux.conf`, `~/.claude/CLAUDE.md`, `~/.claude/statusline-combined.sh` (node path fix),
     `~/.claude/hooks/agent-push.sh` (copies);
   - restores **missing** baseline files from `config/claude/` (sounds, `statusline-sys.sh`, claude-hud files,
     ccstatusline settings, local skills); existing ones are never overwritten;
   - `~/.claude/settings.json`: seeded from `settings.mac.json` if absent; then `settings.orchestrator.json` is
     deep-merged and one `~/.claude/hooks/agent-push.sh` group (async) is appended to `Notification` and to `Stop`
     after the existing groups, once. Written only if the content changes;
   - `~/.config/agent-push/topic` (0600): kept if present, else read from Vault `core-secret-ntfy-topic` (oci CLI,
     best effort), else a new `openssl rand -hex 16`. A new topic must be stored in Vault (`[H]`, rotate-secrets);
   - one line in `~/.zshrc` that sources the snippet (`am`, `ac`); the existing aliases are untouched;
   - `Host cloud` (`User agent`, ControlMaster) appended to `~/.ssh/config` unless a `Host cloud` exists;
   - `~/.config/cmux/cmux.json` from `config/mac/cmux.json` only if absent or still cmux's all-comments template;
   - renders `~/Library/LaunchAgents/cc-orchestrator.claude.agents.plist` and bootstraps it (re-bootstrapped only
     when the plist changed). The `.relay` agent is installed once `bin/agent-relay` exists (Phase 5).
   The LaunchAgent execs `/opt/homebrew/bin/tmux new-session -d -s cc-start ~/.local/bin/cc-orchestrator-start`, so
   the scripts (in `~/Documents`, TCC-protected) run inside the tmux server. A launchd job that runs a script from
   `~/Documents` directly fails with `Operation not permitted`.
   Not done by `install.sh`: npm/plugin installs and `link` skills (see [below](#restore-the-captured-baseline-by-hand)).
6. `[H]` Accept Remote Control once. The LaunchAgent already started `rc-serve` in tmux window `rc:<repo>`, which
   waits at `Enable Remote Control? (y/n)`: `tmux attach -t rc:cc-orchestrator` → `y` → detach with `Ctrl-b d`.
   (Equivalent: `cd ~/Documents/<any-repo> && claude remote-control` → `y` → Ctrl+C.)
7. `[H]` Full Disk Access (System Settings → Privacy & Security → Full Disk Access → `+`, Cmd+Shift+G):
   `$(realpath /opt/homebrew/bin/tmux)` (the tmux server started by the LaunchAgent at login runs Agent View and the RC
   servers in `~/Documents`), and for phone access (Phase 6) `/usr/libexec/sshd-keygen-wrapper`,
   `$(realpath /opt/homebrew/bin/mosh-server)`. Check after the next login: `tmux ls` shows `agents` and `rc`, and
   `/tmp/cc-orchestrator-start.log` has no `Operation not permitted`.
8. `repo-init <repo>` for each repo in `config/mac/repos.txt` (TTY; accept the trust prompt, `/exit`). It adds
   `.claude/worktrees/` to `.gitignore` and `.env`, `.env.local` to `.worktreeinclude` (commit those once in the repo),
   then runs `rc-servers`. New repo for the app: `repo-init --rc <repo>` (appends to `config/mac/repos.txt`).
9. Phone access (Phase 6): `[H]` System Settings → General → Sharing → Remote Login, allow `nicolas` only;
   `sudo cp config/mac/sshd-100-keys-only.conf /etc/ssh/sshd_config.d/100-keys-only.conf`; Moshi key into
   `~/.ssh/authorized_keys`; toggle Remote Login; firewall allow mosh-server; `sudo pmset -c sleep 0 displaysleep 10`.
10. [verify.md](verify.md) Mac section; `make doctor`.

## Restore the captured baseline by hand

`./install.sh mac` now restores the settings and missing files. This snippet is the manual equivalent and the
only place for the npm + plugin installs, which `install.sh` does not do. Safe to re-run. Run it from the repo root
after step 3 (`claude` logged in).

```bash
ts=$(date +%Y%m%d-%H%M%S); s=~/.claude/settings.json
mkdir -p ~/.claude/skills ~/.claude/plugins/claude-hud ~/.config/ccstatusline
if [ -f "$s" ]; then
  cp "$s" "$s.bak.$ts"
  jq -s '.[0] * .[1]' "$s" config/claude/settings.mac.json > "$s.new" && mv "$s.new" "$s"
else
  cp config/claude/settings.mac.json "$s"
fi
install -m 755 config/claude/statusline-*.sh ~/.claude/
cp -R config/claude/sounds ~/.claude/
cp -R config/claude/skills/. ~/.claude/skills/
cp config/claude/plugins/claude-hud/* ~/.claude/plugins/claude-hud/
[ -f ~/.config/ccstatusline/settings.json ] && cp ~/.config/ccstatusline/settings.json ~/.config/ccstatusline/settings.json.bak.$ts
cp config/claude/ccstatusline/settings.json ~/.config/ccstatusline/settings.json
npm install -g ccstatusline                     # under nvm's default node
jq -r '.marketplaces[] | .repo' config/claude/plugins.json | xargs -n1 claude plugin marketplace add
jq -r '.plugins[] | select(.scope == "user") | .id' config/claude/plugins.json | xargs -n1 claude plugin install
```

Then:
- Project-scoped plugins (`"scope": "project"` in `plugins.json`) are reinstalled from inside that repo:
  `cd ~/Documents/<project> && claude plugin install <id> --scope project`.
- Skills of kind `link` in `config/claude/skills.txt` are reinstalled from the listed source (for `find-skills`:
  the `skills` CLI, e.g. `npx skills add vercel-labs/skills`, then pick `find-skills`, global). Kind `synced` skills come back
  after `/login`.
- `~/.zshrc`: copy the blocks from `config/mac/zshrc.captured` that are missing (back up `~/.zshrc` first).
- The statusline node path is fixed (Phase 3): `statusline-combined.sh` uses `node` from PATH, else nvm's
  default-alias version.
