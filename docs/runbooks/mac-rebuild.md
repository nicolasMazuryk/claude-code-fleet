# Rebuild the Mac

Status: all steps runnable; dry-run drill 2026-10-17 (Phase 7, see `docs/progress/phase-7.md`). `[H]` = human-only.

## Facts
- User `nicolas`; repos in `~/Documents`; node via nvm (`~/.nvm`, default alias v24.x), pnpm via corepack.
- `jq` is `/usr/bin/jq`; gh, rsync in `/opt/homebrew/bin`; cmux and Ghostty installed.
- Tailscale node name **`macbook`** (tailnet `tailnet-example`; was `nicolas-macbook`). Exit node `static-ip` must keep working.
- macOS hostname **`nicolas-macbook`**: ComputerName, LocalHostName and HostName, so it is also the Remote Control
  device name. `[H]` on a new Mac (sudo prompts):
  `for k in ComputerName LocalHostName HostName; do sudo scutil --set $k nicolas-macbook; done`.
  Check: `scutil --get ComputerName; scutil --get LocalHostName; scutil --get HostName; hostname`.

## Steps
1. Homebrew; `brew install tmux mosh shellcheck bats-core gh rsync` (mosh installed in Phase 2); install cmux + Ghostty; nvm + `nvm install 24 && nvm alias default 24 && corepack enable`.
2. `[H]` Tailscale app, log in, rename the machine to `macbook`: admin console → machine → Edit machine name (turn
   off auto-generate); `tailscale set --hostname=macbook` only works if it was never renamed in the console. Re-select the
   exit node `static-ip` if needed. Details: [tailscale](tailscale.md) §4.
2a. `[H]` macOS Application Firewall (on, stealth mode): allow mosh, else mosh to cloud (and later phone → Mac) gets
   no UDP. The rule is per binary, on the Homebrew **Cellar** realpath (sudo prompts):
   ```bash
   fw=/usr/libexec/ApplicationFirewall/socketfilterfw
   for b in mosh-client mosh-server; do p=$(realpath /opt/homebrew/bin/$b); sudo $fw --add "$p"; sudo $fw --unblockapp "$p"; done
   $fw --listapps | grep -A1 mosh      # both "Allow incoming connections"
   ```
   `brew upgrade mosh` changes the Cellar path (e.g. `…/mosh/1.4.0_43/…`), which drops the rule: re-run the loop after
   every mosh upgrade. `cc-doctor` (`tcc` line, via `mac-remote-access status`) checks that the allowed mosh-server path is the current Cellar `realpath`.
3. Claude Code: `curl -fsSL https://claude.ai/install.sh | bash`; `[H]` `claude` → `/login`.
4. `cd ~/Documents && gh repo clone nicolasMazuryk/claude-code-fleet && cd claude-code-fleet`.
5. `./install.sh mac` (idempotent; run it from the checkout that should be live, normally
   `~/Documents/claude-code-fleet` on `main`; re-run any time, a second run prints `install.sh mac: no changes`).
   What it does, in order (every overwritten file is backed up first as `<file>.bak.<timestamp>`):
   - `brew install tmux mosh` if missing;
   - symlinks `bin/*` → `~/.local/bin/` (and drops links to scripts that no longer exist);
   - writes `~/.config/cc-orchestrator/config` from `config/mac/config.tmpl` (`CC_ORCH_DIR` = this checkout) and
     copies `config/mac/zshrc.snippet` → `~/.config/cc-orchestrator/zshrc.snippet` (a copy, not a link: phone
     ssh/mosh shells can't read `~/Documents`; re-run `./install.sh mac` after editing the snippet);
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
     when the plist changed). It also copies `bin/agent-relay` + `bin/agent-present` to
     `~/.local/libexec/cc-orchestrator/` (launchd can't read `~/Documents`) and bootstraps
     `cc-orchestrator.claude.relay` (cloud sounds + presence), re-bootstrapping it when the copies change. After
     editing either script, re-run `./install.sh mac`. It also bootstraps `cc-orchestrator.claude.egress-cert` (daily
   `egress-cert-renew`: the egress gateway certificate; needs `brew install lego` and Keychain `cc-cf-acme-dns-token`,
   otherwise it logs a skip; see [browser.md](browser.md)). Check: `tail /tmp/agent-relay.log` →
     `connected to cloud, waiting for events`.
   The LaunchAgent execs `/opt/homebrew/bin/tmux new-session -d -s cc-start ~/.local/bin/cc-orchestrator-start`, so
   the scripts (in `~/Documents`, TCC-protected) run inside the tmux server. A launchd job that runs a script from
   `~/Documents` directly fails with `Operation not permitted`.
   Not done by `install.sh`: npm/plugin installs and `link` skills (see [below](#restore-the-captured-baseline-by-hand)).
6. `[H]` Accept Remote Control once. The acceptance is **global**: `y` stores `remoteDialogSeen: true` in
   `~/.claude.json`, and later `claude remote-control` runs do not ask again. But every `rc:<repo>` window that was
   started before the acceptance is already waiting at `Enable Remote Control? (y/n)` and does not re-read it. So
   answer once, then restart the rest:
   ```bash
   tmux attach -t rc:claude-code-fleet   # y, then detach with Ctrl-b d
   tmux kill-session -t rc && rc-servers # every window restarts without the prompt
   ```
   (Equivalent: type `y` in each `rc:<repo>` window.)
7. `[H]` Full Disk Access (System Settings → Privacy & Security → Full Disk Access → `+`, Cmd+Shift+G):
   `$(realpath /opt/homebrew/bin/tmux)` (the tmux server started by the LaunchAgent at login runs Agent View and the RC
   servers in `~/Documents`). Not by default for `sshd-keygen-wrapper` / `mosh-server` (phone logins): the phone
   attaches to that tmux server; see [iphone-setup § Full Disk Access](iphone-setup.md#full-disk-access-for-remote-logins). Check after the next login: `tmux ls` shows `agents` and `rc`, and
   `/tmp/cc-orchestrator-start.log` has no `Operation not permitted`.
8. `repo-init <repo>` for each repo in `config/mac/repos.txt` (TTY; accept the trust prompt, `/exit`). Trust is per
   directory (`projects["<dir>"].hasTrustDialogAccepted` in `~/.claude.json`); check which are missing with
   `jq -r '.projects|to_entries[]|select(.value.hasTrustDialogAccepted)|.key' ~/.claude.json`. A repo with no commit
   yet cannot create worktrees: make an initial commit first. It adds
   `.claude/worktrees/` to `.gitignore` and `.env`, `.env.local` to `.worktreeinclude` (commit those once in the repo),
   then runs `rc-servers`. New repo for the app: `repo-init --rc <repo>` (appends to `config/mac/repos.txt`).
9. Phone access (Phase 6), in this order ([iphone-setup](iphone-setup.md) §A, `mac-remote-access status` shows what
   is missing):
   1. `[H]` System Settings → General → Sharing → Remote Login on, only `nicolas`, "full disk access for remote users" off;
   2. `mac-remote-access selftest` (throwaway localhost-only key; proves key login, records TCC/Keychain behaviour);
   3. `[H]` Moshi key on the phone → `mac-remote-access add-key <moshi.pub>`; `[H]` Moshi `mac` connects with the key;
   4. `[H]` real terminal: `mac-remote-access apply` (sudo): `/etc/ssh/sshd_config.d/100-keys-only.conf` from
      `config/mac/sshd-100-keys-only.conf` (backup in `/etc/ssh/`, `sshd -t`), `pmset -c sleep 0 displaysleep 10`,
      mosh-server firewall allow (step 2a). Refuses without a phone key and a working key login. Re-run → `no changes`.
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
