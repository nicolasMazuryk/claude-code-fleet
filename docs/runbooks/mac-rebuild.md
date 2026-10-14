# Rebuild the Mac

Status: skeleton. Steps marked (Phase N) become runnable when that phase lands.

## Facts
- User `nicolas`; repos in `~/Documents`; node via nvm (`~/.nvm`, default alias v24.x), pnpm via corepack.
- `jq` is `/usr/bin/jq`; gh, rsync in `/opt/homebrew/bin`; cmux and Ghostty installed.
- Tailscale node name **`macbook`** (tailnet `tailnet-example`; was `nicolas-macbook-pro`). Exit node `static-ip` must keep working.

## Steps
1. Homebrew; `brew install tmux mosh shellcheck bats-core gh rsync`; install cmux + Ghostty; nvm + `nvm install 24 && nvm alias default 24 && corepack enable`.
2. `[H]` Tailscale app, log in, rename: `tailscale set --hostname=macbook` and/or admin console → machine → Edit name. (Phase 2)
3. Claude Code: `curl -fsSL https://claude.ai/install.sh | bash`; `[H]` `claude` → `/login`.
4. `cd ~/Documents && gh repo clone nicolasMazuryk/cc-orchestrator && cd cc-orchestrator`.
5. `./install.sh mac` (Phase 3) — symlinks `bin/*` → `~/.local/bin`, writes `~/.config/cc-orchestrator/config`,
   `~/.tmux.conf`, `~/.claude/CLAUDE.md`, applies `config/claude/` (backup first, deep-merge), appends agent-push
   hooks, ntfy topic (from Vault or new), LaunchAgents, zsh snippet, cmux.json, statusline fix.
   Before Phase 3, restore the captured baseline by hand from `config/claude/` (Phase 1).
6. `[H]` Accept Remote Control once: `cd ~/Documents/<any-repo> && claude remote-control` → `y` → Ctrl+C.
7. `[H]` Full Disk Access (System Settings → Privacy & Security → Full Disk Access → `+`, Cmd+Shift+G):
   `/opt/homebrew/bin/tmux` (resolve with `realpath`), and for phone access `/usr/libexec/sshd-keygen-wrapper`,
   `$(realpath /opt/homebrew/bin/mosh-server)`.
8. `repo-init --rc <repo>` for each repo in `config/mac/repos.txt` (TTY; accept trust).
9. Phone access (Phase 6): `[H]` System Settings → General → Sharing → Remote Login, allow `nicolas` only;
   `sudo cp config/mac/sshd-100-keys-only.conf /etc/ssh/sshd_config.d/100-keys-only.conf`; Moshi key into
   `~/.ssh/authorized_keys`; toggle Remote Login; firewall allow mosh-server; `sudo pmset -c sleep 0 displaysleep 10`.
10. [verify.md](verify.md) Mac section; `make doctor`.
