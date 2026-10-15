# Rebuild the Mac

Status: skeleton. Steps marked (Phase N) become runnable when that phase lands.

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
5. `./install.sh mac` (Phase 3) — symlinks `bin/*` → `~/.local/bin`, writes `~/.config/cc-orchestrator/config`,
   `~/.tmux.conf`, `~/.claude/CLAUDE.md`, applies `config/claude/` (backup first, deep-merge), appends agent-push
   hooks, ntfy topic (from Vault or new), LaunchAgents, zsh snippet, cmux.json, statusline fix.
   Until Phase 3 lands, restore the captured baseline by hand: see [below](#restore-the-captured-baseline-by-hand).
6. `[H]` Accept Remote Control once: `cd ~/Documents/<any-repo> && claude remote-control` → `y` → Ctrl+C.
7. `[H]` Full Disk Access (System Settings → Privacy & Security → Full Disk Access → `+`, Cmd+Shift+G):
   `/opt/homebrew/bin/tmux` (resolve with `realpath`), and for phone access `/usr/libexec/sshd-keygen-wrapper`,
   `$(realpath /opt/homebrew/bin/mosh-server)`.
8. `repo-init --rc <repo>` for each repo in `config/mac/repos.txt` (TTY; accept trust).
9. Phone access (Phase 6): `[H]` System Settings → General → Sharing → Remote Login, allow `nicolas` only;
   `sudo cp config/mac/sshd-100-keys-only.conf /etc/ssh/sshd_config.d/100-keys-only.conf`; Moshi key into
   `~/.ssh/authorized_keys`; toggle Remote Login; firewall allow mosh-server; `sudo pmset -c sleep 0 displaysleep 10`.
10. [verify.md](verify.md) Mac section; `make doctor`.

## Restore the captured baseline by hand

Use this until `./install.sh mac` exists (Phase 3). It is safe to re-run: it backs up and deep-merges settings, and
the copies overwrite with identical content. Run it from the repo root after step 3 (`claude` logged in).

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
- Known bug carried in the baseline: `statusline-combined.sh` hardcodes node v24.13.0, so the claude-hud half of the
  statusline is blank. Phase 3 fixes it, and the fixed copy is captured.
