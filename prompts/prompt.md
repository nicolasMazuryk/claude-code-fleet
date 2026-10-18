# Parallel Claude Code agents: MacBook + cloud + iPhone

*"cloud" is your OCI A1 instance. There are two control paths that work side by side:*
- ***terminal-native:** Agent View in tmux, reached over mosh;*
- ***the Claude app:** Remote Control.*

---

## 0. What you get

| Need | How |
|---|---|
| Many isolated agents across many repos | **Agent View** (`claude agents`) on each machine. Every dispatched session moves into its own git worktree before its first edit, and `.worktreeinclude` copies `.env` files into it. Sessions started from the Claude app also get their own worktree |
| Start sessions, from the Mac | cmux workspace "Agents" with two panes: `am` (Mac Agent View) and `ac` (cloud Agent View). Type `@repo task`. Or use claude.ai/code in a browser |
| Start sessions, from the iPhone | **Terminal:** a mosh app opens either Agent View; type `@repo task`. **App:** Claude app → Code → the `mac/<repo>` or `cloud/<repo>` Remote Control server → new session |
| Manage running sessions from either device | **Terminal:** the same tmux screens from the Mac and the iPhone (peek, reply, attach, stop). **App:** every Remote Control session on both machines (approve, answer, `/model`, stop) |
| Manage the Mac's sessions from the iPhone | macOS Remote Login + mosh over Tailscale, or the Claude app |
| One overview in the terminal | `fleet` lists every session on both machines in one table, waiting-for-you first |
| Same Claude Code configuration on both machines | `cc-sync-settings` copies the Mac's settings, `CLAUDE.md`, skills, agents, commands, output styles, keybindings and hook scripts to cloud |
| Notification sounds | Your existing Mac sound hooks stay exactly as they are: same events, matchers and the Choo Choo sound. Cloud uses the same events and matchers, and its sounds play on the MacBook through `agent-relay` |
| iPhone alerts | ntfy, **only when you're away from the MacBook**: screen locked, Mac asleep, or no keyboard, mouse or trackpad input for 2 minutes. Covers both machines |
| Hands-on work | cmux workspace per repo, `claude -w <name>`, diff viewer and browser pane. These sessions also appear in the Claude app automatically |

**Why two Agent Views.** Background sessions are local to the machine that runs them, so each machine has its own Agent View. For the terminal there's `fleet`. For the app, the Claude app's Code tab lists the Remote Control sessions of both machines in one place.

---

## 1. Architecture

```
                     ┌──────────────────── iPhone ─────────────────────┐
                     │  Moshi/Blink (mosh)      ntfy        Claude app  │
                     └───┬───────────┬───────────▲─────────────▲───────┘
               mosh mac  │           │mosh cloud │ push         │ Remote Control
            ┌────────────┘           │           │ (away only)  │ (outbound-only via Anthropic)
            ▼                        ▼           │              │
┌─────────── MacBook ─────────────┐  ┌─────────── cloud (OCI A1) ───────────┐
│ tmux "agents" → Agent View      │  │ tmux "fleet" → Agent View            │
│ tmux "rc" → RC server per repo  │  │ tmux "rc"    → RC server per repo    │
│ sessions in repo/.claude/       │  │ sessions in repo/.claude/            │
│   worktrees/<name>              │  │   worktrees/<name>                   │
│ hooks: your sound (Choo Choo)   │  │ hooks: same events/matchers; sound → │
│        agent-push → ntfy ───────┼──┼──►    cc-relay-hook → events.jsonl  │
│                                 │  │        agent-push  → ntfy            │
│ agent-relay ══ ssh ═════════════┼═►│ events → your Mac sound hook runs    │
│   presence beacon (30 s) ═══════┼═►│ mac-present marker → push gating     │
│ cc-sync-settings ═══════════════┼═►│ settings, CLAUDE.md, skills, hooks…  │
│ cmux · fleet                    │  │ @reboot cc-orchestrator-start        │
└─────────────────────────────────┘  └──────────────────────────────────────┘
  Tailscale: Mac and iPhone → cloud allowed; cloud → Mac/iPhone blocked (§5).
  Sounds, presence and settings all travel over connections the Mac opens.
```

---

## 2. Shared building blocks

Write these files on the **Mac**. The scripts are copied to cloud once (§3.2); Claude Code configuration is mirrored with `cc-sync-settings` (§4.7). Make every script in `~/.local/bin` executable:

```bash
chmod +x ~/.local/bin/* ~/.claude/hooks/*.sh
```

### 2.1 Per-machine settings: `~/.config/cc-orchestrator/config`

This is the only file that differs between the machines.

```bash
# Mac
AGENT_HOST=mac                    # label in pushes, fleet and the Claude app
AGENTS_ROOT="$HOME/Projects"      # ← the folder that holds your repos on the Mac (set yours)
AGENTS_SESSION=agents             # tmux session running Agent View
AGENT_PERMISSION_MODE=auto        # for sessions dispatched from Agent View or started from the Claude app
```

```bash
# cloud
AGENT_HOST=cloud
AGENTS_ROOT="$HOME/src"           # ← the folder that holds your repos on cloud (set yours)
AGENTS_SESSION=fleet
AGENT_PERMISSION_MODE=auto
```

Shared environment for all scripts, `~/.local/bin/agent-env`. It is sourced, not executed. Background sessions inherit the PATH of whatever started them, so this file guarantees that `node` and `pnpm` are always found:

```bash
# agent-env — sourced by the cc-orchestrator scripts: tools on PATH, UTF-8, node via fnm, per-machine config
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/share/fnm:$PATH"
if [ "$(uname)" = Darwin ]; then export LANG=${LANG:-en_US.UTF-8}; else export LANG=${LANG:-C.UTF-8}; fi
command -v fnm >/dev/null 2>&1 && eval "$(fnm env --shell bash)"   # adjust if you use nvm/volta
. "$HOME/.config/cc-orchestrator/config"
: "${AGENTS_ROOT:?set AGENTS_ROOT in ~/.config/cc-orchestrator/config}" "${AGENT_HOST:?set AGENT_HOST}"
```

### 2.2 Prepare a repo with one command: `~/.local/bin/repo-init`

`repo-init <name | path | git-url>` clones the repo if needed and sets it up on this machine. Running it again is harmless.

```bash
#!/usr/bin/env bash
# repo-init <name | path | git-url> — make a repo ready for isolated parallel agents on this machine (idempotent)
set -euo pipefail
. ~/.local/bin/agent-env
arg=${1:?usage: repo-init <name|path|git-url>}
case $arg in
  *://*|git@*) dir="$AGENTS_ROOT/$(basename "$arg" .git)"; [ -d "$dir" ] || git clone "$arg" "$dir" ;;
  /*)          dir=$arg ;;
  *)           dir="$AGENTS_ROOT/$arg" ;;
esac
cd "$dir" && git rev-parse --git-dir >/dev/null
grep -qxF '.claude/worktrees/' .gitignore 2>/dev/null || echo '.claude/worktrees/' >> .gitignore
for f in ${REPO_INIT_INCLUDE:-.env .env.local}; do                 # gitignored files copied into every worktree
  grep -qxF "$f" .worktreeinclude 2>/dev/null || echo "$f" >> .worktreeinclude
done
echo "→ Accept the workspace trust prompt, then type /exit"
claude
~/.local/bin/rc-servers                                            # start this repo's Remote Control server
r=$(basename "$dir")
echo "✓ $r ready on $AGENT_HOST: Agent View → @$r · Claude app → $AGENT_HOST/$r"
```

Examples:

```bash
repo-init git@github.com:nicolasMazuryk/api.git   # clone into $AGENTS_ROOT and set up
repo-init web                                     # an existing repo in $AGENTS_ROOT
REPO_INIT_INCLUDE=".env .env.local .env.test" repo-init api
```

Notes:
- **Commit the setup files once.** Commit `.gitignore` and `.worktreeinclude` in each repo; the other machine then has them already.
- **Location:** keep repos directly inside `$AGENTS_ROOT`. Agent View's `@` list and `rc-servers` only see repos one level below it.
- **Removing a repo:** delete the directory, then close its window in the `rc` tmux session (`tmux kill-window -t rc:<repo>`).

### 2.3 `~/.claude/CLAUDE.md` (global rules for every agent)

```markdown
# Agent rules
- In a fresh worktree, install dependencies first with the repo's package manager
  (pnpm install --frozen-lockfile / npm ci) before running anything else.
- Run only the tests affected by your change unless asked for the full suite.
```

`cc-sync-settings` copies this file to cloud.

### 2.4 Start Agent View and the Remote Control servers

**`~/.local/bin/agents-loop`** keeps Agent View alive and restarts it after `Esc`. It is launched from the repos root, so `@repo` dispatch works.

```bash
#!/usr/bin/env bash
# agents-loop — keep Claude Code's Agent View alive (restarts after Esc), launched from the repos root
. ~/.local/bin/agent-env
cd "$AGENTS_ROOT" || exit 1
while :; do claude agents --permission-mode "${AGENT_PERMISSION_MODE:-auto}" "$@"; sleep 2; done
```

**`~/.local/bin/rc-serve`** runs one Remote Control server for one repo. Each session you start from the Claude app gets its own worktree. `--spawn worktree` only works inside a git repo, which is why there is one server per repo.

```bash
#!/usr/bin/env bash
# rc-serve <repo-dir> — Remote Control server for one repo; app-started sessions each get their own worktree
. ~/.local/bin/agent-env
cd "$1" || exit 1
while :; do
  claude remote-control --name "$AGENT_HOST/$(basename "$PWD")" --spawn worktree \
    --permission-mode "${AGENT_PERMISSION_MODE:-auto}" --no-create-session-in-dir \
    --remote-control-session-name-prefix "$AGENT_HOST"
  sleep 10
done
```

**`~/.local/bin/rc-servers`** starts one server window per repo in tmux session `rc`, skipping any that are already running.

```bash
#!/usr/bin/env bash
# rc-servers — one Remote Control server per git repo under $AGENTS_ROOT (tmux session "rc", one window per repo)
. ~/.local/bin/agent-env
tmux -u has-session -t rc 2>/dev/null || tmux -u new-session -d -s rc -n idle 'tail -f /dev/null'
for d in "$AGENTS_ROOT"/*/; do
  d=${d%/}; r=$(basename "$d")
  [ -d "$d/.git" ] || continue
  tmux list-windows -t rc -F '#W' | grep -qxF "$r" || tmux new-window -d -t rc -n "$r" "$HOME/.local/bin/rc-serve '$d'"
done
```

**`~/.local/bin/cc-orchestrator-start`** is run at boot or login on both machines.

```bash
#!/usr/bin/env bash
# cc-orchestrator-start — idempotent: Agent View in tmux + Remote Control servers for every repo
. ~/.local/bin/agent-env
tmux -u has-session -t "$AGENTS_SESSION" 2>/dev/null ||
  tmux -u new-session -d -s "$AGENTS_SESSION" "$HOME/.local/bin/agents-loop"
"$HOME/.local/bin/rc-servers"
```

### 2.5 `~/.tmux.conf`

```tmux
set -g mouse on                 # tap/scroll on the phone
set -g window-size latest       # Mac and iPhone can attach at once; size follows the active one
set -sg escape-time 10          # snappy ←/Esc for agent view
set -g history-limit 50000
set -g focus-events on
set -g set-titles on            # passes "2 awaiting input · claude agents" to the outer terminal (cmux sidebar)
set -g set-titles-string '#T'
```

### 2.6 Claude Code settings (the Mac is the source of truth)

Merge these keys into the Mac's `~/.claude/settings.json`. Leave everything else in that file as it is.

```json
{
  "remoteControlAtStartup": true,
  "inputNeededNotifEnabled": false,
  "agentPushNotifEnabled": false,
  "env": { "CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX": "mac" }
}
```

- **`remoteControlAtStartup: true`:** every interactive session connects to the Claude app automatically.
- **Native app push off:** ntfy is the single push channel because it knows when you're away. The app's own push only knows whether you're focused on the terminal.

Cloud gets the same file through `cc-sync-settings` (§4.7), plus the cloud-only values in `~/.config/cc-orchestrator/cloud-settings.json`. That file lives **on the Mac** and is deep-merged on top:

```json
{
  "permissions": { "defaultMode": "auto" },
  "env": { "CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX": "cloud" }
}
```

### 2.7 Sounds and iPhone pushes

**Your Mac sound hooks are the reference and stay unchanged:** the events, the matchers and the Choo Choo sound. When `cc-sync-settings` copies them to cloud:
- It keeps every event and matcher.
- It replaces each macOS-only handler, such as the one that plays Choo Choo, with a `cc-relay-hook` stand-in. When that fires on cloud, the Mac's `agent-relay` (§4.3) runs **your own Mac handler** on the Mac. You hear exactly the sound you hear for local sessions.

| Piece | On the Mac | On cloud |
|---|---|---|
| Your sound hook (Choo Choo) | Runs as you configured it | Same events and matchers. `cc-relay-hook` queues the event, and the Mac runs your handler |
| `agent-present` | Present if the screen is unlocked **and** there was keyboard, mouse or trackpad input in the last 120 s | Present if the Mac's relay refreshed `mac-present` in the last 90 s |
| `agent-push.sh` (hook) | Pushes to ntfy only when `agent-present` fails | Same |

**`~/.local/bin/agent-present`:**

```bash
#!/usr/bin/env bash
# agent-present — exit 0 when you're at the MacBook.
# Mac: unlocked + any keyboard/mouse/trackpad input within AGENT_AWAY_SECS (120). cloud: Mac relay marker < 90 s old.
if [ "$(uname)" = Darwin ]; then
  ioreg -n Root -d1 2>/dev/null | grep -q '"CGSSessionScreenIsLocked"=Yes' && exit 1
  idle=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')   # resets on any HID input
  [ "${idle:-999999}" -lt "${AGENT_AWAY_SECS:-120}" ]
else
  f="$HOME/.local/state/agent-events/mac-present"
  [ -f "$f" ] && [ $(( $(date +%s) - $(stat -c %Y "$f") )) -lt 90 ]
fi
```

**`~/.local/bin/cc-relay-hook`** is the cloud stand-in for a Mac-only hook handler. You never write it into settings yourself; `cc-sync-settings` puts it there.

```bash
#!/usr/bin/env bash
# cc-relay-hook <event> <group> <handler> <hash> — cloud stand-in for a Mac-only hook handler (e.g. your sound):
# queues the event so the Mac's agent-relay runs your own Mac handler on the Mac.
p=; [ -t 0 ] || p=$(cat)
dir="$HOME/.local/state/agent-events"; mkdir -p "$dir"; f="$dir/events.jsonl"
[ "$(stat -c %s "$f" 2>/dev/null || echo 0)" -gt 1048576 ] && : > "$f"        # keep the queue small
jq -nc --arg e "$1" --argjson g "$2" --argjson h "$3" --arg s "$4" --arg p "$p" \
  '{event:$e, group:$g, handler:$h, sum:$s, ts:(now|floor),
    payload:(try ($p | fromjson | if (.last_assistant_message | type) == "string"
                                  then .last_assistant_message |= .[0:500] else . end) catch {})}' >> "$f"
exit 0
```

**`~/.claude/hooks/agent-push.sh`** pushes to the iPhone only when you're away. It covers:
- Agent View events (needs input, done) for background sessions,
- permission prompts and turn ends of interactive sessions: hands-on sessions and those started from the Claude app.

```bash
#!/usr/bin/env bash
# agent-push.sh — Claude Code hook: push to the iPhone (ntfy) only when you're away from the MacBook. Same file on both machines.
. ~/.config/cc-orchestrator/config 2>/dev/null
p=$(cat)
~/.local/bin/agent-present && exit 0                       # at the Mac: sounds are enough
j() { jq -r "$1 // empty" <<<"$p" 2>/dev/null; }
[ -n "$(j .agent_id)" ] && exit 0                          # subagent events
ev=$(j .hook_event_name); t=$(j .notification_type)
case "$ev:$t" in
  Notification:agent_needs_input) kind="needs input" ;;    # fired by Agent View for any background session
  Notification:agent_completed)   kind="done" ;;
  *) [ -n "${CLAUDE_JOB_DIR:-}" ] && exit 0                # a background session itself: Agent View already reports it
     case "$ev:$t" in
       Notification:permission_prompt|Notification:elicitation_dialog) kind="needs input" ;;
       Stop:) kind="done" ;;
       *) exit 0 ;;
     esac ;;
esac
msg=$(j '.message // .last_assistant_message' | tr '\n' ' ' | cut -c1-140)
prio=default; tags=white_check_mark
[ "$kind" = "needs input" ] && { prio=high; tags=warning; }
click=()                                                   # tap opens the session in the Claude app / claude.ai
[ -n "${CLAUDE_CODE_BRIDGE_SESSION_ID:-}" ] && click=(-H "Click: https://claude.ai/code/$CLAUDE_CODE_BRIDGE_SESSION_ID")
curl -fsS -m 5 -H "Title: ${AGENT_HOST:-$(hostname -s)} · $kind" -H "Priority: $prio" -H "Tags: $tags" "${click[@]}" \
  -d "${msg:-$kind}" "${NTFY_SERVER:-https://ntfy.sh}/$(cat ~/.config/agent-push/topic)" >/dev/null 2>&1
exit 0
```

**Add `agent-push.sh` to the Mac's hooks.** Append one new group to `Notification` and one to `Stop`, *after* your existing groups. Your Choo Choo groups keep their position, events and matchers. `cc-sync-settings` relies on that position to identify them.

```jsonc
{
  "hooks": {
    "Notification": [
      // … your existing Notification group(s) with the Choo Choo sound — unchanged …
      { "hooks": [ { "type": "command", "command": "~/.claude/hooks/agent-push.sh", "async": true } ] }
    ],
    "Stop": [
      // … your existing Stop group(s), if any — unchanged …
      { "hooks": [ { "type": "command", "command": "~/.claude/hooks/agent-push.sh", "async": true } ] }
    ]
  }
}
```

**ntfy topic.** Create it once on the Mac and subscribe to it in the ntfy iPhone app:

```bash
mkdir -p ~/.config/agent-push && openssl rand -hex 16 > ~/.config/agent-push/topic
```

Topics are public by name, so keep it unguessable. The push body carries at most 140 characters of the session's message.

### 2.8 `~/.local/bin/fleet` (Mac): one table for both machines

```bash
#!/usr/bin/env bash
# fleet — every Claude Code session on the Mac and on cloud, waiting-for-you first
q='.[] | [$h, (.state // .status // "?"), (.waitingFor // ""),
   (.cwd | sub("/\\.claude/worktrees/.*$"; "") | split("/") | last),
   (.name // "-"), (.id // "interactive")] | @tsv'
{
  claude agents --json 2>/dev/null | jq -r --arg h mac "$q"
  ssh -o ConnectTimeout=5 cloud '~/.local/bin/claude agents --json' 2>/dev/null | jq -r --arg h cloud "$q"
} | sort -t$'\t' -k2,2 | column -t -s$'\t'
```

The columns are host, state, waiting-for, repo, name and id.
- **States:** `blocked` means it needs you; `working`, `done`, `failed` and `stopped` are as named. Interactive sessions (hands-on, or started from the app) show `busy`, `waiting` or `idle`.
- **Direction:** the Mac reaches cloud over SSH. Nothing on cloud can reach the Mac (§5).

---

## 3. Cloud (OCI A1, Ubuntu 24.04)

### 3.1 Bootstrap (once)

Create the `tag:cloud` tag in the Tailscale policy first (§5), then run:

```bash
sudo apt-get update && sudo apt-get install -y git tmux mosh jq curl rsync ripgrep build-essential gh tig
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh --hostname cloud --advertise-tags=tag:cloud
sudo iptables -I INPUT -i tailscale0 -p udp --dport 60000:61000 -j ACCEPT      # mosh, tailnet only
sudo sh -c 'command -v netfilter-persistent >/dev/null && netfilter-persistent save' || true
curl -fsSL https://fnm.vercel.app/install | bash
export PATH="$HOME/.local/share/fnm:$PATH"; eval "$(fnm env)"; fnm install --lts; corepack enable   # pnpm
curl -fsSL https://claude.ai/install.sh | bash
claude            # /login with your claude.ai account, then /exit
gh auth login
loginctl enable-linger "$USER"
```

Close port 22 in the OCI security list. Tailscale SSH and mosh over the tailnet are the only ways in.

### 3.2 Copy the scripts and mirror the settings (run on the Mac)

```bash
ssh cloud 'mkdir -p ~/.local/bin ~/.claude ~/.config/agent-push ~/.config/cc-orchestrator ~/src'
scp ~/.local/bin/{agent-env,agents-loop,cc-orchestrator-start,rc-servers,rc-serve,repo-init,agent-present,cc-relay-hook} cloud:.local/bin/
scp ~/.tmux.conf cloud:
scp ~/.config/agent-push/topic cloud:.config/agent-push/
ssh cloud 'chmod +x ~/.local/bin/*'
cc-sync-settings          # settings.json, CLAUDE.md, skills, agents, commands, hooks… (§4.7)
```

Then, on cloud, write `~/.config/cc-orchestrator/config` (the cloud variant in §2.1).

### 3.3 Start everything at boot

1. **Accept Remote Control once.** Run `claude remote-control` in any repo, answer `y`, then press `Ctrl+C`.
2. **Prepare each repo:** `repo-init <git-url or name>` (§2.2).
3. **Start at boot.** Add to `crontab -e`:
   ```cron
   @reboot /home/ubuntu/.local/bin/cc-orchestrator-start
   ```
4. **Start now:** `~/.local/bin/cc-orchestrator-start`. This creates tmux sessions `fleet` (Agent View) and `rc` (one Remote Control server per repo).

### 3.4 Disk and RAM

- **pnpm:** its content-addressed store hard-links packages across worktrees.
- **Worktree cleanup:** Claude Code's default sweep removes old background-session and subagent worktrees after `cleanupPeriodDays`. It keeps any worktree that still holds uncommitted changes or unpushed commits. Agents commit without pushing, so finished work stays until you delete its session.
- **Monitoring:** check `du -sh "$AGENTS_ROOT"/*/.claude/worktrees`, `df -h` and `free -h` weekly at first.
- **Budget:** each Remote Control server is one idle Claude Code process per repo. Agents running builds and tests in parallel are what saturate a 2 OCPU / 12 GB A1.

---

## 4. MacBook

### 4.1 Packages and files

```bash
brew install tmux mosh jq
brew tap manaflow-ai/cmux && brew install --cask cmux
sudo ln -sf /Applications/cmux.app/Contents/Resources/bin/cmux /usr/local/bin/cmux
```

Then:
- **Files:** write everything in §2 (the Mac config variant in §2.1), plus `agent-relay` (§4.3) and `cc-sync-settings` (§4.7). Make them executable.
- **Tailscale:** install the macOS app and join the same tailnet with the device name `macbook`.
- **Remote Control:** accept it once by running `claude remote-control` in any repo, answering `y`, then pressing `Ctrl+C`.
- **Repos:** run `repo-init` for each one.

### 4.2 `~/.ssh/config`

```sshconfig
Host cloud
  HostName cloud
  User ubuntu
  ServerAliveInterval 20
  ServerAliveCountMax 3
  ControlMaster auto
  ControlPath ~/.ssh/cm-%C
  ControlPersist 10m
```

Check it works with `ssh cloud true`. Tailscale SSH authenticates by tailnet identity, so no key is needed.

### 4.3 Hear cloud sounds and report presence: `~/.local/bin/agent-relay`

This is one long-running process on the Mac with two jobs:
- for every relayed hook event from cloud, it runs **your own Mac hook handler**, so you hear Choo Choo;
- every 30 s it tells cloud whether you're at the Mac, which is what gates cloud's iPhone pushes.

```bash
#!/usr/bin/env bash
# agent-relay (Mac, launchd) — 1) for cloud hook events, run your own Mac hook handler (your sound) here
#                              2) tell cloud whether you're at the Mac (gates cloud's iPhone pushes)
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
S='~/.local/state/agent-events'
( while :; do
    if agent-present; then c="mkdir -p $S && touch $S/mac-present"; else c="rm -f $S/mac-present"; fi
    ssh -o BatchMode=yes -o ConnectTimeout=5 cloud "$c" >/dev/null 2>&1
    sleep 30
  done ) & beacon=$!
trap 'kill $beacon 2>/dev/null' EXIT
ssh -o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=2 cloud \
  "mkdir -p $S && touch $S/events.jsonl && tail -n0 -F $S/events.jsonl" |
while IFS= read -r line; do
  IFS=$'\t' read -r ev g h sum < <(jq -r '[.event, .group, .handler, .sum] | @tsv' <<<"$line" 2>/dev/null)
  [[ $ev =~ ^[A-Za-z]+$ && $g =~ ^[0-9]+$ && $h =~ ^[0-9]+$ ]] || continue
  hd=$(jq -c --arg ev "$ev" --argjson g "$g" --argjson h "$h" '.hooks[$ev][$g].hooks[$h] // {}' ~/.claude/settings.json)
  cmd=$(jq -r '.command // empty' <<<"$hd")
  if [ -z "$cmd" ] || [ "$(printf %s "$cmd" | shasum -a 256 | cut -c1-16)" != "$sum" ]; then
    echo "$(date '+%F %T') skipped $ev/$g/$h: Mac hooks changed, run cc-sync-settings" >&2; continue
  fi
  payload=$(jq -c '.payload // {}' <<<"$line")
  args=(); while IFS= read -r a; do args+=("$a"); done < <(jq -r '.args[]?' <<<"$hd")
  if [ ${#args[@]} -gt 0 ]; then
    (printf %s "$payload" | "${cmd/#\~/$HOME}" "${args[@]}") >/dev/null 2>&1 &
  else
    (printf %s "$payload" | sh -c "$cmd") >/dev/null 2>&1 &
  fi
done
```

**Safety:**
- Cloud only says *which* of your Mac's hook handlers fired (event and position), and a hash check confirms it's still the same handler.
- The command itself always comes from the Mac's own `settings.json`, so cloud can't make the Mac run anything new.
- The event payload reaches your handler as data on stdin, just as it does for local sessions.
- Everything travels over the Mac's own SSH connection; cloud never connects to the Mac.

### 4.4 Start at login (launchd)

Replace `YOU` with your macOS username in both files.

`~/Library/LaunchAgents/cc-orchestrator.claude.agents.plist` runs Agent View and the Remote Control servers. It runs inside your logged-in session, so `claude` can read its login from the Keychain.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>cc-orchestrator.claude.agents</string>
  <key>ProgramArguments</key><array><string>/Users/YOU/.local/bin/cc-orchestrator-start</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
```

`~/Library/LaunchAgents/cc-orchestrator.claude.relay.plist` is the sound relay plus presence beacon, restarted automatically:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>cc-orchestrator.claude.relay</string>
  <key>ProgramArguments</key><array><string>/Users/YOU/.local/bin/agent-relay</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>StandardErrorPath</key><string>/tmp/agent-relay.log</string>
</dict></plist>
```

```bash
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/cc-orchestrator.claude.agents.plist
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/cc-orchestrator.claude.relay.plist
```

### 4.5 Let the iPhone into the Mac

1. **Turn on Remote Login.** *System Settings → General → Sharing → Remote Login* (allow your user only).
2. **Allow key-only logins.** Create `/etc/ssh/sshd_config.d/100-keys-only.conf`:
   ```
   PasswordAuthentication no
   KbdInteractiveAuthentication no
   ```
   Add the iPhone app's public key to `~/.ssh/authorized_keys`, then toggle Remote Login off and on. Plain `sshd` over the tailnet is used here, because Tailscale SSH isn't available with the standard macOS Tailscale app.
3. **mosh:** the client needs the full server path, `/opt/homebrew/bin/mosh-server`. If the macOS firewall is on, allow it:
   ```bash
   sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "$(realpath /opt/homebrew/bin/mosh-server)"
   sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$(realpath /opt/homebrew/bin/mosh-server)"
   ```
4. **Stay awake while you're away.** A sleeping Mac can't be reached by the terminal or by the Claude app; its sessions are preserved and resume on wake. On the charger: `sudo pmset -c sleep 0 displaysleep 10`, and keep the lid open. Long jobs belong on cloud.

### 4.6 Shell shortcuts (`~/.zshrc`) and cmux

```bash
alias am='tmux -u new -A -s agents ~/.local/bin/agents-loop'                 # agents mac
alias ac='mosh cloud -- tmux -u new -A -s fleet ~/.local/bin/agents-loop'    # agents cloud
alias ca='claude agents'
```

`~/.config/cmux/cmux.json` (trimmed):

```json
{
  "$schema": "https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json",
  "schemaVersion": 1,
  "app": { "newWorkspacePlacement": "afterCurrent", "reorderOnNotification": "agentActivity", "confirmQuit": "dirty-only" },
  "terminal": { "copyOnSelect": false, "autoResumeAgentSessions": true, "predictiveLocalEcho": true },
  "sidebar": { "showPullRequests": true, "pathLastSegmentOnly": true, "branchLayout": "inline" },
  "automation": { "claudeCodeIntegration": true },
  "browser": { "defaultSearchEngine": "google", "openTerminalLinksInCmuxBrowser": true },
  "commands": [
    { "name": "Agents: Mac",   "keywords": ["agents", "mac"],   "command": "tmux -u new -A -s agents ~/.local/bin/agents-loop" },
    { "name": "Agents: cloud", "keywords": ["agents", "cloud"], "command": "mosh cloud -- tmux -u new -A -s fleet ~/.local/bin/agents-loop" },
    { "name": "Agents: fleet", "keywords": ["agents", "all"],   "command": "watch -n 15 ~/.local/bin/fleet" }
  ]
}
```

- **"Agents" workspace (pinned, top of the sidebar):** split it, then run `am` in the left pane and `ac` in the right. The tab titles show "N awaiting input".
- **Per-repo workspaces:** for hands-on work only, using `claude -w <name>`, the diff viewer and the browser pane. These sessions also show up in the Claude app.
- **Ghostty config:** keep whatever you like; it's cosmetic.

### 4.7 Mirror Claude Code settings to cloud: `~/.local/bin/cc-sync-settings`

This makes cloud's Claude Code configuration a copy of the Mac's. Run it after any change on the Mac.

| Synced | How |
|---|---|
| `~/.claude/settings.json`, every key | Copied. Mac home paths become cloud home paths. The cloud-only values in `~/.config/cc-orchestrator/cloud-settings.json` are deep-merged on top |
| Hooks | Same events and matchers. macOS-only handlers (e.g. your Choo Choo sound) become `cc-relay-hook` stand-ins that the Mac's `agent-relay` plays on the Mac |
| `CLAUDE.md`, `keybindings.json`, `skills/`, `agents/`, `commands/`, `output-styles/`, `hooks/` | Mirrored. Anything you deleted on the Mac is deleted on cloud |

```bash
#!/usr/bin/env bash
# cc-sync-settings — mirror the Mac's Claude Code user configuration to cloud (Mac = source of truth).
# macOS-only hook handlers (your sounds) become cc-relay-hook stand-ins: cloud keeps the same events and
# matchers, and the Mac's agent-relay runs your own handler on the Mac.
set -eo pipefail
MAC_ONLY=${CC_MAC_ONLY:-'afplay|osascript|terminal-notifier|/usr/bin/say|say -v'}
src="$HOME/.claude/settings.json"
overrides="$HOME/.config/cc-orchestrator/cloud-settings.json"
cloud_home=$(ssh cloud 'printf %s "$HOME"')

is_mac_only() {                      # the command, or the script it runs, uses a macOS-only tool
  local f
  grep -qE "$MAC_ONLY" <<<"$1" && return 0
  f=$(awk '{print $1}' <<<"$1"); f=${f//\"/}; f=${f//\'/}; f=${f/#\~/$HOME}
  [ -f "$f" ] && grep -qE "$MAC_ONLY" "$f"
}

s=$(cat "$src"); relayed=0
while IFS=$'\t' read -r ev g h; do
  cmd=$(jq -r --arg ev "$ev" --argjson g "$g" --argjson h "$h" '.hooks[$ev][$g].hooks[$h].command' "$src")
  is_mac_only "$cmd" || continue
  sum=$(printf %s "$cmd" | shasum -a 256 | cut -c1-16)
  s=$(jq --arg ev "$ev" --argjson g "$g" --argjson h "$h" --arg c "~/.local/bin/cc-relay-hook $ev $g $h $sum" \
        '.hooks[$ev][$g].hooks[$h] = {type: "command", command: $c, async: true}' <<<"$s")
  relayed=$((relayed + 1))
done < <(jq -r '(.hooks // {}) | to_entries[] | .key as $ev | .value | to_entries[] | .key as $g
                | .value.hooks | to_entries[] | select(.value.type == "command") | [$ev, $g, .key] | @tsv' "$src")

s=$(jq --arg mh "$HOME" --arg ch "$cloud_home" 'walk(if type == "string" then gsub($mh; $ch) else . end)' <<<"$s")
[ -f "$overrides" ] && s=$(jq -s '.[0] * .[1]' <(printf '%s' "$s") "$overrides")
printf '%s\n' "$s" | ssh cloud 'f=~/.claude/settings.json; cat > "$f.tmp" && mv "$f.tmp" "$f"'

cd "$HOME/.claude"
items=(); for i in CLAUDE.md keybindings.json skills agents commands output-styles hooks; do [ -e "$i" ] && items+=("$i"); done
[ ${#items[@]} -gt 0 ] && rsync -a --delete "${items[@]}" cloud:.claude/
echo "✓ cloud mirrors the Mac's Claude Code settings · $relayed macOS-only hook handler(s) relayed to the Mac"
```

Notes:
- **Sound detection:** the summary line must report at least 1 relayed handler; that is your Choo Choo hook. If it reports 0, your sound command uses a tool not in the list. Set `CC_MAC_ONLY` to a pattern that matches it, for example `CC_MAC_ONLY='afplay|my-sound-tool' cc-sync-settings`.
- **Not synced:** your login, `~/.claude.json` (workspace trust and user-scope MCP servers), session history and plugin installs. Add user-scope MCP servers on cloud once with `claude mcp add --scope user …`. If a plugin enabled in your settings is missing on cloud, install it there with `/plugin`.

---

## 5. Tailscale policy (security)

Your devices can reach everything. Cloud, which runs agents with full access, can't initiate connections to the Mac or the phone. Sounds, presence and settings sync still work, because the Mac opens every connection.

```jsonc
{
  "tagOwners": { "tag:cloud": ["autogroup:admin"] },
  "acls": [
    { "action": "accept", "src": ["autogroup:member"], "dst": ["*:*"] }
    // no rule with src tag:cloud → cloud can't open connections into the tailnet
  ],
  "ssh": [
    { "action": "accept", "src": ["autogroup:member"], "dst": ["tag:cloud"], "users": ["ubuntu"] }
  ]
}
```

Apply it in the admin console *before* running `tailscale up --advertise-tags=tag:cloud`. Never put a key for the Mac on cloud.

For the Claude app, optionally turn on **Require trusted devices** in your claude.ai account settings. Every device that steers a Remote Control session then needs to be enrolled and recently signed in.

---

## 6. iPhone

1. **Tailscale app:** same tailnet.
2. **Terminal app with mosh:** Moshi (free) or Blink Shell. Generate a key in the app and add its public key to the Mac's `~/.ssh/authorized_keys`. Cloud needs no key, because Tailscale SSH authenticates by tailnet identity.
3. **Two hosts:**

   | Host | Address | mosh server | Command on connect |
   |---|---|---|---|
   | `cloud` | `cloud` (user `ubuntu`) | default | `tmux -u new -A -s fleet ~/.local/bin/agents-loop` |
   | `mac` | `macbook` | `/opt/homebrew/bin/mosh-server` | `tmux -u new -A -s agents ~/.local/bin/agents-loop` |

   If the app has no "command on connect" field, type the command after connecting.
4. **ntfy app:** subscribe to your topic. Pushes arrive only while you're away from the Mac.
5. **Claude app:** sign in with the same claude.ai account. The **Code** tab lists the Remote Control servers and sessions of both machines. Its own notifications can stay off; ntfy covers alerts.
6. **Keyboard:** turn on the extra-keys row (arrows, Ctrl, Esc). Agent View is driven by `↑ ↓ ← →`, `Space`, `Enter` and `Ctrl+…`.

For the terminal overview, open a second tmux window on the `mac` host (`Ctrl-b c`) and run `fleet`.

---

## 7. Daily use

### 7.1 Start work

| Where you are | Run on the Mac | Run on cloud |
|---|---|---|
| Mac, at the desk | Left pane: `@repo the task` → `Enter` (`Ctrl+Enter` dispatches and opens it) | Right pane, same |
| Mac, inside a repo shell | `claude --bg --name short-name "the task"` | — |
| iPhone, terminal | `mac` host → `@repo the task` | `cloud` host → `@repo the task` |
| iPhone or browser, Claude app | Code → `mac/<repo>` server → new session | Code → `cloud/<repo>` server → new session |
| Hands-on pairing | cmux workspace for the repo → `claude -w feat-x` | `ac`, then attach |

Long, unattended or heavy work goes to **cloud**. Quick or interactive work, or anything that needs Mac-only tools, stays on the **Mac**.

### 7.2 Manage

**In the terminal (Agent View):**

| Action | Keys |
|---|---|
| Show only what needs you | type `s:blocked` |
| Group by repo / by state | `Ctrl+S` |
| Read the question or result | `Space` (peek) |
| Answer a question | type in the peek box → `Enter` |
| Answer a **permission prompt** | `→` to attach, answer, `←` to detach |
| Open the full conversation | `Enter` / `→` (you get a recap of what happened while you were away) |
| Change model for a session | peek → `/model sonnet` |
| Ask an agent to push or open a PR | peek → "push the branch and open a PR" |
| Pin (keep the process warm) / rename | `Ctrl+T` / `Ctrl+R` |
| Stop / delete (removes its worktree) | `Ctrl+X` / `Ctrl+X` twice |
| Bring back an old session | type `/resume` |
| Make a background session reachable from the app | attach (`→`) → `/remote-control` → `←`. Only needed if it isn't already listed (§10) |

**In the Claude app (Code tab):** open any session from either machine to reply, approve prompts, change `/model` or `/effort`, `/compact`, or stop it. Tapping an ntfy push for an interactive session opens it there directly.

### 7.3 Leaving the desk

- **Away means:** the Mac is locked, asleep, or has had no keyboard, mouse or trackpad input for 2 minutes. From then on, both machines push to the phone. Cloud picks up the change within 30 s.
- **At the Mac:** you hear Choo Choo for both machines, and the phone stays quiet.
- **Hands-on sessions:** these are in the Claude app already. To reach one from the phone *terminal*, press `←` on an empty prompt before leaving; it moves into the Mac's Agent View and keeps running.
- **Mac sessions working while you're away:** leave the Mac on the charger with the lid open (§4.5).

---

## 8. Limits and recovery

| Situation | What happens / what to do |
|---|---|
| Mac asleep or lid closed | Mac sessions pause and resume on wake. The terminal and the app can't reach them. Cloud keeps working and pushes to the phone |
| Cloud sounds while the Mac is asleep or offline | Not replayed later; the phone push covers that time |
| Mac's connection to cloud is down while you're at the Mac | Cloud can't see your presence, so it pushes to the phone. Extra pushes rather than missed ones |
| You changed settings or hooks on the Mac | Run `cc-sync-settings`. Until you do, a cloud sound whose Mac handler changed is skipped and logged in `/tmp/agent-relay.log` |
| Cloud or Mac reboot | `@reboot` / LaunchAgent restarts Agent View, the Remote Control servers and the relay. Interrupted background sessions show as **failed**: reply "continue" or attach to resume them |
| A Remote Control server restarts (reboot, or more than 10 min without network) | Sessions it was serving are archived in the app. Their transcripts and worktrees stay; resume with `claude --resume` in the repo, or start a new app session |
| App-started sessions | They run in the repo's Remote Control server, not in Agent View. Manage them in the app; `fleet` lists them as interactive |
| Remote Control stops working | It needs your claude.ai login. `ANTHROPIC_API_KEY`, a custom `ANTHROPIC_BASE_URL` or `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` turns it off |
| Pressed `Esc` in Agent View | `agents-loop` reopens it after 2 s. To leave tmux, use `Ctrl-b d` |
| Agent can't find node/pnpm | It was started from a shell without your PATH. Dispatch through Agent View, the app, or an interactive shell |
| "Workspace not trusted" | Run `repo-init <repo>` again and accept the prompt |
| Too many pushes | Raise `AGENT_AWAY_SECS` in the Mac's environment, or mute the topic in ntfy for a while |
| Disk filling up | Delete finished sessions (`Ctrl+X` twice). The default sweep removes old background-session worktrees that have no uncommitted or unpushed work. Use `git worktree list` / `git worktree remove` for anything left over |
| Quota | Each agent uses your subscription independently. Check `/usage` and keep the concurrent count realistic |

---

## 9. Rollout

| Step | Do | Done when |
|---|---|---|
| 1 | Tailscale on all three devices; apply the §5 policy | `ssh cloud` from the Mac works; cloud can't reach the Mac |
| 2 | Mac files (§2, §4) | `am` works; `fleet` lists the Mac's sessions |
| 3 | Cloud (§3) | `cc-sync-settings` reports at least 1 relayed handler. `ac` shows cloud's Agent View. `repo-init` a repo, dispatch `@repo hello`, and the session gets a worktree with `.env` in it |
| 4 | Sounds | Trigger a question in a cloud session and the Mac plays Choo Choo |
| 5 | Pushes | Lock the Mac: pushes arrive from both machines. Unlocked and moving the mouse: none |
| 6 | Remote Control | The Claude app lists `mac/<repo>` and `cloud/<repo>`. Start a session from the app on each machine and approve a prompt from the app |
| 7 | iPhone terminal (§6) | From the phone you can dispatch on both hosts, answer via peek, and approve via attach |

## 10. Check once during rollout

1. **Background sessions in the app:** with `remoteControlAtStartup`, do Agent View background sessions appear in the Claude app? The docs describe auto-connect for interactive sessions. If they don't appear, use attach → `/remote-control` for the ones you want there (§7.2).
2. **Starting from the app:** confirm how the app starts a new session on a server (`cloud/<repo>`) and that the session lands in its own worktree.
3. **`CLAUDE_JOB_DIR` in hooks:** confirm background sessions pass it to hooks (log `env` once from `agent-push.sh`). Otherwise a background session's own permission prompts push in addition to Agent View's "needs input".
4. **Sound relay:** `cc-sync-settings` must count your Choo Choo handler (≥ 1 relayed). If the handler takes its sound from the hook payload, check that the relayed run sounds the same as a local one.
5. **`@` list:** check that it shows every repo in `$AGENTS_ROOT`. Directories with spaces in their names aren't listed.
6. **Mac over SSH:** if `claude` started from an SSH login on the Mac reports no login, that's the Keychain-over-SSH limit. Rely on the LaunchAgent-started sessions.
7. **OCI limits:** check your tenancy's actual A1 allowance in the OCI console.

---

## Sources

- Agent View: https://code.claude.com/docs/en/agent-view
- Remote Control (server mode, `--spawn worktree`, session URLs, mobile push): https://code.claude.com/docs/en/remote-control
- Hooks (Notification types incl. `agent_needs_input`/`agent_completed`, inherited environment, `CLAUDE_CODE_BRIDGE_SESSION_ID`): https://code.claude.com/docs/en/hooks
- Worktrees and `.worktreeinclude`, background-worktree sweep: https://code.claude.com/docs/en/worktrees
- Settings reference (`remoteControlAtStartup`, `inputNeededNotifEnabled`, `agentPushNotifEnabled`, `cleanupPeriodDays`): https://code.claude.com/docs/en/settings-reference
- ntfy: https://ntfy.sh