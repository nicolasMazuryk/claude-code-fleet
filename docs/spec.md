# Spec (adapted): parallel Claude Code agents on macbook + cloud + iPhone

This is `prompts/prompt.md` rewritten for the real machines. Section numbers match the original so the two can be
read side by side. Where this file is silent, the original applies **with the substitutions in §A**.

**Precedence:** the scripts in `bin/`, `hooks/` and `config/` (once they exist) > this file > `prompts/prompt.md`.
Code here is the design reference for the phase that implements it; the phase number is given per item.

## A. Substitutions (apply everywhere)

| Original | Real | Why |
|---|---|---|
| `~/Projects` (Mac `AGENTS_ROOT`) | `~/Documents` | 32 repos live there |
| `~/src` (cloud `AGENTS_ROOT`) | `/data/fleet` | persistent 100 GB `/data` volume |
| cloud user `ubuntu`, home `/home/ubuntu` | user **`agent`**, home `/data/home/agent` | oci bootstrap creates `agent`; survives restore |
| host `cloud` on port 22 | `core-vm-app`, Tailscale node `cloud` (`tag:cloud`), no public IP | [ADR 0001](decisions/0001-tailscale-on-oci.md) |
| Mac Tailscale name `macbook` | rename `nicolas-macbook-pro` → `macbook` (tailnet `tailnet-example`) | Phase 2 |
| fnm | Mac: nvm (`~/.nvm`, Node 24); cloud: system Node 24 (NodeSource) | real setup |
| `@reboot` cron on cloud | systemd `cc-agents.service` + `cc-rc@<repo>.service`, `loginctl enable-linger agent` | systemd is already used by oci |
| cloud tmux session `rc` | one systemd unit per repo (`cc-rc@<repo>`) | successor of oci `agent@<repo>` |
| RC server for every repo | only repos in `config/<host>/repos.txt` | [ADR 0003](decisions/0003-repos-allowlist.md) |
| 1 Choo Choo hook | **4** `afplay ~/.claude/sounds/choo-choo.mp3` handlers | real Mac settings |
| files hand-written into `~/.local/bin` | files in this repo, symlinked by `install.sh` | single source of truth |
| `~/.config/cc-orchestrator/cloud-settings.json` | `config/claude/cloud-settings.json` (in repo) | versioned |
| Blink or Moshi | Moshi (Blink documented as alternative) | plan default |

## 0. What you get

Unchanged from the original §0, with: Mac pane `am` = tmux `agents` on the Mac; cloud pane `ac` = `mosh cloud` →
tmux `fleet` as user `agent`; the Claude app lists `mac/<repo>` and `cloud/<repo>` **for allowlisted repos only**.

## 1. Architecture

See [architecture.md](architecture.md).

## 2. Shared building blocks

### 2.1 Per-machine config: `~/.config/cc-orchestrator/config` (written by `install.sh`, Phase 3/4)

```bash
# Mac
AGENT_HOST=mac
AGENTS_ROOT="$HOME/Documents"
AGENTS_SESSION=agents
AGENT_PERMISSION_MODE=auto
CC_ORCH_DIR="$HOME/Documents/cc-orchestrator"
REPOS_FILE="$CC_ORCH_DIR/config/mac/repos.txt"
```

```bash
# cloud
AGENT_HOST=cloud
AGENTS_ROOT=/data/fleet
AGENTS_SESSION=fleet
AGENT_PERMISSION_MODE=auto
CC_ORCH_DIR=/data/home/agent/cc-orchestrator      # rsynced by install.sh cloud
REPOS_FILE="$CC_ORCH_DIR/config/cloud/repos.txt"
```

`bin/agent-env` (sourced, not executed) — nvm instead of fnm:

```bash
# agent-env — sourced by cc-orchestrator scripts: PATH, UTF-8, node, per-machine config
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
if [ "$(uname)" = Darwin ]; then
  export LANG=${LANG:-en_US.UTF-8}
  export NVM_DIR=${NVM_DIR:-$HOME/.nvm}
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" --no-use && nvm use --silent default >/dev/null
else
  export LANG=${LANG:-C.UTF-8}             # cloud: system node from NodeSource, no manager
fi
. "$HOME/.config/cc-orchestrator/config"
: "${AGENTS_ROOT:?set AGENTS_ROOT in ~/.config/cc-orchestrator/config}" "${AGENT_HOST:?set AGENT_HOST}"
```

On cloud `$HOME` is `/data/home/agent`, so `~/.local/bin` is `/data/home/agent/.local/bin` (where the Claude Code
binary lives).

### 2.2 `bin/repo-init <name | path | git-url> [--rc]` (Phase 3)

As the original, plus:
- a bare name on **cloud** that is not cloned yet is cloned from `https://github.com/nicolasMazuryk/<name>.git`
  into `/data/fleet/<name>` (HTTPS via the gh PAT from Vault, as oci `fleet add` did);
- `--rc` appends the repo name to `$REPOS_FILE` if missing (then commit that file in this repo);
- it runs `rc-servers` only when the repo is in `$REPOS_FILE`;
- the trust step (`claude`, accept, `/exit`) needs a human at a TTY.

Commit `.gitignore` (`.claude/worktrees/`) and `.worktreeinclude` (`.env`, `.env.local`) in each repo once.
Repo directory names must have no spaces (Agent View's `@` list skips them).

### 2.3 Global agent rules: `config/claude/CLAUDE.md` → `~/.claude/CLAUDE.md` (Phase 3)

Content as the original §2.3 (install deps first, run affected tests, commit on the worktree branch, never push or
open a PR unless asked). The Mac currently has no `~/.claude/CLAUDE.md`; `install.sh mac` creates it.

### 2.4 Agent View and Remote Control servers

- `bin/agents-loop`: as the original.
- `bin/rc-serve <repo-dir>`: as the original (`--name "$AGENT_HOST/<repo>" --spawn worktree --permission-mode
  "$AGENT_PERMISSION_MODE" --no-create-session-in-dir --remote-control-session-name-prefix "$AGENT_HOST"`), loop with
  `sleep 10`. On cloud the loop is unnecessary (systemd restarts) but harmless.
- `bin/rc-servers`: reconciles against `$REPOS_FILE`:

```bash
#!/usr/bin/env bash
# rc-servers — one Remote Control server per repo in $REPOS_FILE (idempotent reconcile)
. ~/.local/bin/agent-env
want=$(grep -vE '^\s*(#|$)' "$REPOS_FILE" | sed 's/[[:space:]]*#.*//' | sort -u)
if [ "$AGENT_HOST" = cloud ]; then
  for r in $want; do
    [ -d "$AGENTS_ROOT/$r/.git" ] || { echo "skip $r: not cloned (repo-init $r)" >&2; continue; }
    systemctl is-enabled --quiet "cc-rc@$r" && systemctl is-active --quiet "cc-rc@$r" || sudo systemctl enable --now "cc-rc@$r"
  done
  for u in $(systemctl list-units 'cc-rc@*' --all --plain --no-legend | awk '{print $1}'); do
    r=${u#cc-rc@}; r=${r%.service}
    grep -qxF "$r" <<<"$want" || sudo systemctl disable --now "$u"
  done
else
  tmux -u has-session -t rc 2>/dev/null || tmux -u new-session -d -s rc -n idle 'tail -f /dev/null'
  for r in $want; do
    d="$AGENTS_ROOT/$r"; [ -d "$d/.git" ] || { echo "skip $r: not a git repo" >&2; continue; }
    tmux list-windows -t rc -F '#W' | grep -qxF "$r" || tmux new-window -d -t rc -n "$r" "$HOME/.local/bin/rc-serve '$d'"
  done
  tmux list-windows -t rc -F '#W' | while read -r w; do
    [ "$w" = idle ] || grep -qxF "$w" <<<"$want" || tmux kill-window -t "rc:$w"
  done
fi
```

- `bin/cc-orchestrator-start` (Mac only; cloud uses systemd): start tmux `$AGENTS_SESSION` with `agents-loop` if
  missing, then `rc-servers`.

#### Cloud systemd units (`config/cloud/systemd/`, installed by `install.sh cloud`, Phase 4)

`cc-rc@.service` — successor of oci `agent@.service`:

```ini
[Unit]
Description=Claude Code Remote Control server for %i (cc-orchestrator)
After=network-online.target data.mount tailscaled.service
Wants=network-online.target
RequiresMountsFor=/data

[Service]
Type=simple
User=agent
WorkingDirectory=/data/fleet/%i
Environment=HOME=/data/home/agent
ExecStart=/data/home/agent/.local/bin/rc-serve /data/fleet/%i
Restart=always
RestartSec=30
CPUWeight=200

[Install]
WantedBy=multi-user.target
```

Logs go to journald (`journalctl -u cc-rc@<repo>`). Interacting with a server (first-run prompts) is done by
running `rc-serve` once by hand as `agent` (see [add-repo](runbooks/add-repo.md)), not by attaching to the unit.
Phase 4 decides whether `rc-serve` needs a pty wrapper (`script -qfc`) under systemd; record it here.

`cc-agents.service` — Agent View in tmux session `fleet` (replaces the original `@reboot` cron):

```ini
[Unit]
Description=Claude Code Agent View in tmux "fleet" (cc-orchestrator)
After=network-online.target data.mount
RequiresMountsFor=/data

[Service]
Type=forking
User=agent
Environment=HOME=/data/home/agent
ExecStart=/usr/bin/tmux -u new-session -d -s fleet /data/home/agent/.local/bin/agents-loop
ExecStop=/usr/bin/tmux kill-session -t fleet
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### 2.5 `config/mac/tmux.conf` → `~/.tmux.conf` (both hosts)

As the original §2.5.

### 2.6 Claude Code settings (Mac = source of truth)

`config/claude/settings.orchestrator.json` (deep-merged into the Mac's settings by `install.sh mac`, backup first):

```json
{
  "remoteControlAtStartup": true,
  "inputNeededNotifEnabled": false,
  "agentPushNotifEnabled": false,
  "env": { "CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX": "mac" }
}
```

Today the Mac has both notif flags `true` and no `remoteControlAtStartup`; these keys flip them.

`config/claude/cloud-settings.json` (deep-merged on top for cloud by `cc-sync-settings`):

```json
{
  "permissions": { "defaultMode": "auto" },
  "env": { "CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX": "cloud" }
}
```

Statusline bug: `~/.claude/statusline-combined.sh` hardcodes node v24.13.0, which is gone. Fix it to use
`$(command -v node)` or `$NVM_DIR/versions/node/$(cat "$NVM_DIR/alias/default")` (Phase 3), and capture the fixed
copy into `config/claude/statusline-combined.sh`.

### 2.7 Sounds and iPhone pushes

Mac hooks today (reference; keep positions):

| Event | Matcher | Handler |
|---|---|---|
| `Stop` | — | jq-guarded `afplay ~/.claude/sounds/choo-choo.mp3` |
| `Notification` | `permission_prompt\|elicitation_dialog` | `afplay ~/.claude/sounds/choo-choo.mp3` |
| `PreToolUse` | `AskUserQuestion\|ExitPlanMode` | `afplay ~/.claude/sounds/choo-choo.mp3` |
| `StopFailure` | — | `afplay ~/.claude/sounds/choo-choo.mp3` |

- `install.sh mac` appends one `hooks/agent-push.sh` group to `Notification` and one to `Stop`, **after** the existing
  groups, idempotently (match on the command string). The hook path in settings is
  `~/.claude/hooks/agent-push.sh` (installed as a copy/symlink of `hooks/agent-push.sh`).
- `bin/agent-present`, `bin/cc-relay-hook`, `hooks/agent-push.sh`: as the original §2.7. On cloud `stat -c` is GNU,
  fine. The ntfy topic is `~/.config/agent-push/topic` (0600), recovered from Vault `core-secret-ntfy-topic`.
- Relayed `PreToolUse`/`Stop` handlers run on the Mac via `sh -c` with the cloud payload on stdin; the Stop handler's
  jq guard then evaluates the cloud payload, which is the intended behaviour.

### 2.8 `bin/fleet` (Mac)

As the original §2.8 with `ssh cloud` = `agent@cloud` and the remote command
`/data/home/agent/.local/bin/claude agents --json`. Extra subcommands carried over from oci's CLI:

| Command | Does |
|---|---|
| `fleet` | the merged table (default) |
| `fleet logs <host> <repo>` | cloud: `journalctl -u cc-rc@<repo> -f`; mac: `tmux capture-pane -p -t rc:<repo>` |
| `fleet restart <host> <repo>` | cloud: `sudo systemctl restart cc-rc@<repo>`; mac: kill + recreate the `rc:<repo>` window |
| `fleet attach <host> <repo>` | mac: `tmux attach -t rc:<repo>`; cloud: Agent View (`ac`), since units run without tmux |

## 3. Cloud (`core-vm-app`, Ubuntu 24.04 arm64)

### 3.1 Bootstrap — owned by `~/Documents/oci` (Phase 2/4, via oci PRs)

The machine part of the original §3.1 is done by oci `host/app/bootstrap.sh` and `make host-sync VM=app`:
packages (git, tmux, mosh, jq, rsync, gh, build-essential, …), Node 24 + corepack, `agent` user + linger,
gh auth from `core-secret-github-pat`, Tailscale, and the mosh rule (as implemented in Phase 2, oci `setup_tailscale`):

```bash
# only when the node has no state; the key is read from a 0600 temp file, never put on argv
tailscale up --ssh --hostname=cloud --advertise-tags=tag:cloud --accept-dns=false \
  --auth-key="file:$keyfile"            # keyfile ← secret_get core-secret-tailscale-authkey
allow_udp_on_iface tailscale0 60000:61000   # iptables -I before the image's REJECT + the same line in rules.v4
```

tailscaled keeps its state on `/data/core/tailscale` (systemd drop-in), so a restore rejoins as the same node.
Rules are added to `rules.v4` by line, not with `netfilter-persistent save`, which would also persist Docker's and
Tailscale's own chains. Details: [runbooks/tailscale.md](runbooks/tailscale.md).

There is **no** "close port 22" step: port 22 was never public (NSG allows it only from the Bastion endpoint).
Human, once: `sudo -iu agent claude auth login` (persists on `/data`).

### 3.2 Install from the Mac: `./install.sh cloud` (Phase 4)

Replaces the original's `scp` list: rsync this repo to `/data/home/agent/cc-orchestrator`, symlink `bin/*` into
`/data/home/agent/.local/bin`, write the cloud config, install tmux.conf, the ntfy topic, the systemd units, migrate
`agent@*` → `cc-rc@*`, then run `cc-sync-settings`.

### 3.3 Start at boot

systemd (`cc-agents`, `cc-rc@<repo>`), enabled by `install.sh cloud` / `rc-servers`. Human, once: accept Remote
Control (`claude remote-control` in any repo as `agent`, `y`, Ctrl+C) and workspace trust per repo (`repo-init`).

### 3.4 Disk and RAM

As the original. Real numbers: 2 OCPU / 12 GB + 16 GB swap; `/data` 100 GB; block storage is at the free-tier cap
(200/200 GB), so **no new volumes**. Check `du -sh /data/fleet/*/.claude/worktrees`, `df -h /data`, `free -h`.

## 4. MacBook

### 4.1 Packages

`brew install tmux mosh shellcheck bats-core` (jq is `/usr/bin/jq`; cmux and Ghostty are already installed; gh and
rsync are in `/opt/homebrew`). Then `./install.sh mac`. Tailscale node renamed to `macbook`.

### 4.2 `~/.ssh/config` (snippet `config/mac/ssh_config.snippet`, appended by `install.sh mac`)

```sshconfig
Host cloud
  HostName cloud
  User agent
  ServerAliveInterval 20
  ServerAliveCountMax 3
  ControlMaster auto
  ControlPath ~/.ssh/cm-%C
  ControlPersist 10m
```

Tailscale SSH authenticates by tailnet identity; the policy allows users `agent` and `ubuntu` on `tag:cloud`.

### 4.3 `bin/agent-relay`

As the original §4.3 (hash-checked; runs the Mac's own handler). Log: `/tmp/agent-relay.log`.

### 4.4 LaunchAgents (`config/mac/launchd/*.plist.tmpl`, rendered with real paths by `install.sh mac`)

`cc-orchestrator.claude.agents` (RunAtLoad → `~/.local/bin/cc-orchestrator-start`) and
`cc-orchestrator.claude.relay` (KeepAlive, ThrottleInterval 30, stderr `/tmp/agent-relay.log`).
Loaded with `launchctl bootstrap gui/$(id -u) …` (idempotent: `bootout` first if loaded).

**macOS TCC gotcha:** processes started by launchd, sshd or mosh-server that touch `~/Documents` need Full Disk
Access (or Files & Folders → Documents) for `/opt/homebrew/bin/tmux`, `/usr/libexec/sshd-keygen-wrapper` and
`/opt/homebrew/bin/mosh-server`. Manual, in System Settings → Privacy & Security; checked by `cc-doctor`.

### 4.5 Let the iPhone into the Mac (Phase 6, manual)

Remote Login **off today** → on, for user `nicolas` only; `config/mac/sshd-100-keys-only.conf` →
`/etc/ssh/sshd_config.d/100-keys-only.conf`; Moshi public key in `~/.ssh/authorized_keys`; firewall allow for
`mosh-server`; `sudo pmset -c sleep 0 displaysleep 10`.

### 4.6 Shell shortcuts (`config/mac/zshrc.snippet`, sourced from `~/.zshrc`) and cmux

```bash
alias am='tmux -u new -A -s agents ~/.local/bin/agents-loop'
alias ac='mosh cloud -- tmux -u new -A -s fleet ~/.local/bin/agents-loop'
# fleet is ~/.local/bin/fleet (on PATH)
```

The existing aliases `c`, `ca`, `cw`, `cbg` are kept as they are (captured in Phase 1). `config/mac/cmux.json` →
`~/.config/cmux/cmux.json` as the original §4.6.

### 4.7 `bin/cc-sync-settings`

As the original §4.7, plus:
- home rewrite `/Users/nicolas` → `/data/home/agent` (the original's `$HOME` → remote `$HOME` already does this);
- drop Mac-only keys: `statusLine` (unless the script is portable, then copy it too), `enabledPlugins["warp@…"]`,
  `preferredNotifChannel`;
- overrides from `config/claude/cloud-settings.json`;
- list plugins enabled on the Mac but missing on cloud and print the `claude plugin install …` commands (or run them
  with `--install-plugins`), never silently;
- **must report `4 macOS-only hook handler(s) relayed`.** Fewer means a hook changed: investigate before continuing.

## 5. Tailscale policy — `config/tailscale/policy.hujson` (Phase 2)

The full policy **as applied**, i.e. the existing policy (incl. exit node `static-ip` rules/autoApprovers) merged with:

```jsonc
{
  "tagOwners": { "tag:cloud": ["autogroup:admin"] },
  "acls": [
    { "action": "accept", "src": ["autogroup:member"], "dst": ["*:*", "autogroup:internet:*"] }
    // no rule with src tag:cloud
  ],
  "ssh": [
    { "action": "accept", "src": ["autogroup:member"], "dst": ["tag:cloud"], "users": ["agent", "ubuntu"] }
  ]
}
```

`autogroup:internet:*` keeps the exit node `static-ip` usable. The tailnet default allow-all (`src: ["*"]`) must be
removed. The file also has `tests`/`sshTests` blocks, so Tailscale rejects a save that breaks the invariants.
Applied by a human in the admin console **before** `tailscale up --advertise-tags=tag:cloud`
([runbooks/tailscale.md](runbooks/tailscale.md)).

## 6. iPhone (Phase 6) — `config/iphone/hosts.md`

| Host | Address | User / auth | mosh server | Command on connect |
|---|---|---|---|---|
| `cloud` | `cloud` | `agent`, Tailscale SSH (no key) | default | `tmux -u new -A -s fleet ~/.local/bin/agents-loop` |
| `mac` | `macbook` | `nicolas`, Moshi key | `/opt/homebrew/bin/mosh-server` | `tmux -u new -A -s agents ~/.local/bin/agents-loop` |

Plus: Tailscale app, ntfy subscription to the topic, Claude app (own notifications off), extra-keys row.

## 7–8. Daily use, limits and recovery

As the original §7–§8, with: "`@reboot`" → systemd on cloud; "Run `cc-sync-settings`" → also `make capture` + commit
when the Mac's settings changed; disk checks on `/data`.

## 9–10. Rollout and checks

Real-name versions in [runbooks/verify.md](runbooks/verify.md).
