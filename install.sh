#!/usr/bin/env bash
# install.sh mac | cloud — install cc-orchestrator on this host. Idempotent: a second run changes nothing.
#
#   ./install.sh mac     (run on the Mac, from the checkout that should be live; usually ~/Documents/claude-code-fleet)
#   ./install.sh cloud [--dry-run | --rollback]   (run on the Mac; installs on cloud over `ssh cloud` as agent, sudo where needed)
#
# mac, in order (each step prints "ok" when already in place, "updated"/"created" when it wrote something):
#   tools       brew install tmux mosh if missing
#   bin         ~/.local/bin/<script> → <repo>/bin/<script> (symlinks; editing the repo changes what runs)
#   config      ~/.config/cc-orchestrator/config (from config/mac/config.tmpl), zshrc.snippet copy
#   tmux        ~/.tmux.conf
#   claude      ~/.claude/CLAUDE.md, statusline-combined.sh (node path fix), hooks/agent-push.sh;
#               baseline files from config/claude/ only where missing (sounds, skills, claude-hud, ccstatusline,
#               profile/*, memory/<dir> → ~/.claude/projects/<dir>/memory)
#   settings    ~/.claude/settings.json: seeded from settings.mac.json if absent; settings.orchestrator.json
#               deep-merged; one agent-push.sh group appended to Notification and Stop (once); browser-guard PreToolUse
#               groups and the browser-router-relay SessionStart slot (once each). Backup first.
#   ntfy        ~/.config/agent-push/topic (0600): kept if present, else Vault core-secret-ntfy-topic, else new
#   zshrc       one sourcing line for the snippet (am, ac); existing aliases untouched
#   ssh         Host cloud appended to ~/.ssh/config if no Host cloud exists
#   cmux        ~/.config/cmux/cmux.json if absent or still cmux's all-comments template
#   relay       copies of bin/agent-relay, agent-present, browser-up, browser-relay-handler in ~/.local/libexec/cc-orchestrator/ (launchd can't
#               read ~/Documents, TCC); the relay LaunchAgent is restarted when they change
#   launchd     cc-orchestrator.claude.agents and .relay (sound relay + presence beacon), bootstrapped
#
# cloud, from the Mac (--dry-run: show what would change, write nothing on cloud except a staging copy in ~/.cache):
#   sync        rsync this checkout (tracked + new files, not gitignored; not tests/ prompts/) → cloud:~/claude-code-fleet
#               (--delete)
#   ntfy        ~/.config/agent-push/topic copied to cloud (0600) when missing or different
#   cloud-local ~/claude-code-fleet/install.sh cloud-local on cloud (below)
#   settings    cc-sync-settings (expect "4 macOS-only hook handler(s) relayed")
# cloud-local (on cloud as agent; sudo is passwordless there):
#   claude      Claude Code binary for agent (~/.local/bin/claude, native installer) if missing — this repo owns it
#   bin, path   ~/.local/bin → ~/claude-code-fleet/bin (not the Mac-only cc-capture, cc-sync-settings,
#               cc-orchestrator-start, agent-relay, mac-remote-access, browser-up, browser-relay-handler); PATH line at the top of ~/.bashrc (non-interactive ssh)
#   config      ~/.config/cc-orchestrator/config (config/cloud/config.tmpl), ~/.tmux.conf
#   legacy      oci's agent@<repo> units stopped + disabled, agent@.service, /usr/local/bin/fleet and the
#               tmux -L agent-<repo> servers removed (one RC server per folder; ADR 0002)
#   browser     browser-router cloned + built (~/.local/share/browser-router, linked into ~/.local/bin), agent-browser pinned
#   units       cc-rc@.service, cc-agents.service, browser-router-vault-drain.{service,timer} → /etc/systemd/system
#               (timer enabled once browser-router is installed); rsyslog rule → /var/log/core/agent.log
#   linger      loginctl enable-linger agent
#   repos       clone missing config/cloud/repos.txt repos into /data/fleet (gh auth), repo-init --no-trust each
#   agents      cc-agents.service enabled + started (Agent View, tmux session "fleet")
#   rc          rc-servers: cc-rc@<repo> for each listed repo that is cloned and trusted
# cloud --rollback: stop/remove cc-rc@*, cc-agents and the rsyslog rule; restore agent@.service, fleet and the
#   agent@<repo> instances from the copy step "legacy" kept in ~/.local/state/cc-orchestrator/legacy.
#
# Every overwritten user file is backed up first as <file>.bak.<timestamp>.
# Test/CI switches: CC_INSTALL_NO_BREW=1, CC_INSTALL_NO_LAUNCHD=1, CC_INSTALL_NO_VAULT=1 (HOME may be a scratch dir);
# cloud-local: CC_SUDO (default sudo; "" in tests), CC_UNIT_DIR, CC_RSYSLOG_DIR, CC_LOG_DIR, CC_LEGACY_BIN,
# CC_INSTALL_NO_CLAUDE=1, CC_INSTALL_NO_BROWSER=1, CC_BROWSER_DIR, AGENT_BROWSER_VERSION, CC_INSTALL_NO_CLONE=1, CC_DRY_RUN=1, CC_CLOUD_REPO (path written into links/config),
# CC_AGENTS_ROOT, CC_TMUX_DIR, CC_INSTALL_ANY_OS=1.
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
TS=$(date +%Y%m%d-%H%M%S)
changes=0
DRY=${CC_DRY_RUN:-0}

say() { printf '  %-9s %s\n' "$1" "$2"; }
did() { changes=$((changes + 1)); say "$1" "$2"; }
die() { echo "install.sh: $*" >&2; exit 1; }

backup() { # backup <file>: copy to <file>.bak.<ts> if it exists (regular file or symlink)
  [ "$DRY" = 1 ] && return 0
  if [ -e "$1" ] || [ -L "$1" ]; then cp -pP "$1" "$1.bak.$TS"; fi
}

install_file() { # install_file <tag> <src> <dst> <mode>: copy if different, backing up the old one
  local tag=$1 src=$2 dst=$3 mode=$4
  if [ -f "$dst" ] && [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then
    say "$tag" "ok $dst"; return 0
  fi
  if [ "$DRY" = 1 ]; then did "$tag" "would write $dst"; return 0; fi
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] || [ -L "$dst" ]; then backup "$dst"; rm -f "$dst"; did "$tag" "updated $dst (backup .bak.$TS)"
  else did "$tag" "created $dst"; fi
  cp "$src" "$dst"; chmod "$mode" "$dst"
}

install_missing() { # install_missing <tag> <src> <dst>: copy only when dst does not exist (restore baseline)
  local tag=$1 src=$2 dst=$3
  [ -e "$src" ] || return 0
  if [ -e "$dst" ]; then return 0; fi
  mkdir -p "$(dirname "$dst")"
  cp -R "$src" "$dst"; did "$tag" "restored $dst from config/"
}

link() { # link <tag> <target> <linkpath>
  local tag=$1 target=$2 path=$3
  if [ -L "$path" ] && [ "$(readlink "$path")" = "$target" ]; then return 0; fi
  if [ "$DRY" = 1 ]; then did "$tag" "would link $path → $target"; return 0; fi
  mkdir -p "$(dirname "$path")"
  if [ -e "$path" ] && [ ! -L "$path" ]; then backup "$path"; rm -f "$path"; fi
  ln -sfn "$target" "$path"; did "$tag" "$path → $target"
}

# --- steps ----------------------------------------------------------------------------------------
step_tools() {
  local missing=() t
  for t in tmux mosh; do
    command -v "$t" >/dev/null 2>&1 || [ -x "/opt/homebrew/bin/$t" ] || missing+=("$t")
  done
  command -v jq >/dev/null 2>&1 || die "jq not found (macOS ships /usr/bin/jq)"
  command -v claude >/dev/null 2>&1 || [ -x "$HOME/.local/bin/claude" ] ||
    say tools "WARNING: claude not installed (curl -fsSL https://claude.ai/install.sh | bash)"
  if [ ${#missing[@]} -eq 0 ]; then say tools "ok tmux mosh jq"; return 0; fi
  if [ "${CC_INSTALL_NO_BREW:-0}" = 1 ]; then say tools "missing ${missing[*]} (CC_INSTALL_NO_BREW set)"; return 0; fi
  command -v brew >/dev/null 2>&1 || die "missing ${missing[*]} and no Homebrew"
  brew install "${missing[@]}"; did tools "brew installed ${missing[*]}"
}

step_bin() { # links point into $LIVE (the checkout that runs; differs from $REPO only in a cloud dry run)
  local f n before=$changes live=${LIVE:-$REPO}
  for f in "$REPO"/bin/*; do
    n=$(basename "$f")
    [ -x "$f" ] || continue
    [ -f "$f" ] || continue
    case " ${BIN_SKIP:-} " in *" $n "*) continue ;; esac
    link bin "$live/bin/$n" "$HOME/.local/bin/$n"
  done
  # drop links into a cc-orchestrator bin/ whose script no longer exists here
  for f in "$HOME"/.local/bin/*; do
    [ -L "$f" ] || continue
    case $(readlink "$f") in
      */cc-orchestrator*/bin/*) n=$(basename "$f")
        { [ -e "$REPO/bin/$n" ] && case " ${BIN_SKIP:-} " in *" $n "*) false ;; *) true ;; esac; } || {
          [ "$DRY" = 1 ] || rm -f "$f"; did bin "removed stale $f"; } ;;
    esac
  done
  [ "$changes" -ne "$before" ] || say bin "ok ~/.local/bin → $live/bin"
}

step_config() {
  local tmp
  tmp=$(mktemp); sed "s#@CC_ORCH_DIR@#$REPO#g" "$REPO/config/mac/config.tmpl" > "$tmp"
  install_file config "$tmp" "$HOME/.config/cc-orchestrator/config" 644; rm -f "$tmp"
  # a copy, not a link: ssh/mosh shells (phone) cannot read ~/Documents (no Full Disk Access)
  install_file config "$REPO/config/mac/zshrc.snippet" "$HOME/.config/cc-orchestrator/zshrc.snippet" 644
}

step_tmux() { install_file tmux "$REPO/config/mac/tmux.conf" "$HOME/.tmux.conf" 644; }

step_claude() {
  local c="$REPO/config/claude" d="$HOME/.claude"
  install_file claude "$c/CLAUDE.md" "$d/CLAUDE.md" 644
  install_file claude "$c/statusline-combined.sh" "$d/statusline-combined.sh" 755
  install_file claude "$REPO/hooks/agent-push.sh" "$d/hooks/agent-push.sh" 755
  # baseline (Phase 1 capture): restore only what is missing, never overwrite Mac state
  install_missing claude "$c/statusline-sys.sh" "$d/statusline-sys.sh"
  install_missing claude "$c/sounds" "$d/sounds"
  install_missing claude "$c/plugins/claude-hud" "$d/plugins/claude-hud"
  install_missing claude "$c/ccstatusline/settings.json" "$HOME/.config/ccstatusline/settings.json"
  local s
  for s in "$c"/skills/*; do
    [ -d "$s" ] && install_missing claude "$s" "$d/skills/$(basename "$s")"
  done
  for s in "$c"/profile/*; do
    [ -f "$s" ] && install_missing claude "$s" "$d/profile/$(basename "$s")"
  done
  for s in "$c"/memory/*; do
    [ -d "$s" ] && install_missing claude "$s" "$d/projects/$(basename "$s")/memory"
  done
  return 0
}

# shellcheck disable=SC2016
SETTINGS_JQ='
  def addpush($ev):
    .hooks[$ev] = ((.hooks[$ev] // []) as $g
      | if any($g[]?.hooks[]?; (.command // "") | test("agent-push\\.sh")) then $g
        else $g + [{hooks: [{type: "command", command: "~/.claude/hooks/agent-push.sh", async: true}]}] end);
  # browser-router: PreToolUse guard per browser tool family (contracts §9), and the relay slot agent-relay looks up for
  # BrowserLease/Release/Dispatch events (a SessionStart matcher Claude Code never reports, so it only runs from the relay)
  def addguard($m):
    .hooks.PreToolUse = ((.hooks.PreToolUse // []) as $g
      | if any($g[]?; .matcher == $m and any(.hooks[]?; (.command // "") | test("browser-guard"))) then $g
        else $g + [{matcher: $m, hooks: [{type: "command", command: "~/.claude/hooks/browser-guard"}]}] end);
  def addrelay:
    .hooks.SessionStart = ((.hooks.SessionStart // []) as $g
      | if any($g[]?; .matcher == "browser-router-relay") then $g
        else $g + [{matcher: "browser-router-relay", hooks: [{type: "command", command: "~/.local/libexec/cc-orchestrator/browser-relay-handler"}]}] end);
  (.[0] * .[1]) | addpush("Notification") | addpush("Stop")
  | addguard("mcp__claude-in-chrome__.*") | addguard("mcp__computer-use__.*") | addguard("Bash") | addrelay'

step_settings() {
  local s="$HOME/.claude/settings.json" new
  mkdir -p "$HOME/.claude"
  if [ ! -f "$s" ]; then
    cp "$REPO/config/claude/settings.mac.json" "$s"; did settings "seeded $s from config/claude/settings.mac.json"
  fi
  jq empty "$s" 2>/dev/null || die "$s is not valid JSON; fix it first (nothing written)"
  new=$(mktemp "$s.new.XXXXXX")
  jq -s "$SETTINGS_JQ" "$s" "$REPO/config/claude/settings.orchestrator.json" > "$new"
  if [ "$(jq -S . "$s")" = "$(jq -S . "$new")" ]; then
    rm -f "$new"; say settings "ok $s (orchestrator keys + agent-push hooks present)"; return 0
  fi
  backup "$s"; chmod 600 "$new"; mv "$new" "$s"
  did settings "merged settings.orchestrator.json + agent-push hooks into $s (backup .bak.$TS)"
}

vault_get() { # vault_get <secret-name> → value on stdout; fails quietly if oci/Vault is unavailable
  [ "${CC_INSTALL_NO_VAULT:-0}" = 1 ] && return 1
  command -v oci >/dev/null 2>&1 && [ -f "$HOME/.oci/config" ] || return 1
  local prof=${OCI_CLI_PROFILE:-DEFAULT} tenancy core vault
  tenancy=$(awk -F= -v p="[$prof]" '$0==p{f=1;next} /^\[/{f=0} f&&$1~/^tenancy *$/{gsub(/ /,"",$2);print $2}' "$HOME/.oci/config")
  [ -n "$tenancy" ] || return 1
  core=$(oci iam compartment list --compartment-id "$tenancy" --name core --lifecycle-state ACTIVE \
           --query 'data[0].id' --raw-output 2>/dev/null) || return 1
  vault=$(oci kms management vault list --compartment-id "$core" --all --raw-output \
           --query "data[?\"display-name\"=='core-vault' && \"lifecycle-state\"=='ACTIVE'].id | [0]" 2>/dev/null) || return 1
  [ -n "$vault" ] && [ "$vault" != null ] || return 1
  oci secrets secret-bundle get-secret-bundle-by-name --vault-id "$vault" --secret-name "$1" \
    --query 'data."secret-bundle-content".content' --raw-output 2>/dev/null | base64 -D 2>/dev/null
}

step_ntfy() {
  local dir="$HOME/.config/agent-push" f v
  f="$dir/topic"
  ( umask 077; mkdir -p "$dir" ); chmod 700 "$dir"
  if [ -s "$f" ]; then
    [ "$(stat -f %Lp "$f" 2>/dev/null || stat -c %a "$f")" = 600 ] || chmod 600 "$f"
    say ntfy "ok $f (kept)"; return 0
  fi
  if v=$(vault_get core-secret-ntfy-topic) && [ -n "$v" ]; then
    ( umask 077; printf '%s\n' "$v" > "$f" ); did ntfy "created $f from Vault core-secret-ntfy-topic"
  else
    ( umask 077; openssl rand -hex 16 > "$f" )
    did ntfy "created $f (new random topic; store it in Vault: see docs/runbooks/rotate-secrets.md)"
  fi
  unset v
}

ZSHRC_MARK='# cc-orchestrator: am, ac (managed by install.sh mac)'
step_zshrc() {
  local z="$HOME/.zshrc"
  if [ -f "$z" ] && grep -qxF "$ZSHRC_MARK" "$z"; then say zshrc "ok $z"; return 0; fi
  backup "$z"
  printf '\n%s\n%s\n' "$ZSHRC_MARK" '[ -r ~/.config/cc-orchestrator/zshrc.snippet ] && . ~/.config/cc-orchestrator/zshrc.snippet' >> "$z"
  did zshrc "appended snippet line to $z"
}

step_ssh() {
  local c="$HOME/.ssh/config"
  ( umask 077; mkdir -p "$HOME/.ssh" )
  if [ -f "$c" ] && grep -qiE '^[[:space:]]*Host([[:space:]]+[^#]*)?[[:space:]]cloud([[:space:]]|$)' "$c"; then
    say ssh "ok $c (Host cloud present)"; return 0
  fi
  local sep=
  [ -s "$c" ] && sep=$'\n'
  backup "$c"
  printf '%s%s\n' "$sep" "$(cat "$REPO/config/mac/ssh_config.snippet")" >> "$c"
  chmod 600 "$c"; did ssh "appended Host cloud to $c"
}

step_cmux() {
  local c="$HOME/.config/cmux/cmux.json" src="$REPO/config/mac/cmux.json" keys
  if [ -f "$c" ] && cmp -s "$src" "$c"; then say cmux "ok $c"; return 0; fi
  if [ -f "$c" ]; then
    # cmux writes an all-comments template on first launch; only that (or nothing) is replaced
    keys=$(sed -E 's#^[[:space:]]*//.*$##' "$c" | tr '\n' ' ' | sed -E 's/,[[:space:]]*}/}/g' |
           jq -c '[keys[] | select(. != "$schema" and . != "schemaVersion")]' 2>/dev/null || echo unknown)
    if [ "$keys" != "[]" ]; then
      say cmux "kept $c (has your own settings; merge config/mac/cmux.json by hand if wanted)"; return 0
    fi
  fi
  install_file cmux "$src" "$c" 644
}

launchd_load() { # launchd_load <label> <plist> <changed 0|1>
  local label=$1 plist=$2 changed=$3 dom i
  dom="gui/$(id -u)"
  if launchctl print "$dom/$label" >/dev/null 2>&1; then
    [ "$changed" = 1 ] || { say launchd "ok $label (loaded)"; return 0; }
    launchctl bootout "$dom/$label" 2>/dev/null || true
  fi
  for i in 1 2 3 4 5; do
    launchctl bootstrap "$dom" "$plist" 2>/dev/null && { did launchd "bootstrapped $label"; return 0; }
    sleep "$i"
  done
  die "launchctl bootstrap $dom $plist failed"
}

RELAY_CHANGED=0
step_relay() { # launchd jobs can't read ~/Documents (TCC: "Operation not permitted"), so the relay runs from copies
  local d="$HOME/.local/libexec/cc-orchestrator" f before=$changes
  for f in agent-relay agent-present browser-up browser-relay-handler; do
    if [ -f "$d/$f" ] && cmp -s "$REPO/bin/$f" "$d/$f"; then continue; fi
    mkdir -p "$d"; cp "$REPO/bin/$f" "$d/$f.tmp"; chmod 755 "$d/$f.tmp"; mv "$d/$f.tmp" "$d/$f"
    did relay "copied bin/$f → $d/$f"
  done
  if [ "$changes" -ne "$before" ]; then RELAY_CHANGED=1; else say relay "ok $d (agent-relay, agent-present)"; fi
}

step_launchd() {
  local la="$HOME/Library/LaunchAgents" label tmp dst changed tmux_bin
  tmux_bin=$(command -v tmux || echo /opt/homebrew/bin/tmux)
  for label in cc-orchestrator.claude.agents cc-orchestrator.claude.relay; do
    dst="$la/$label.plist"; tmp=$(mktemp)
    sed "s#@HOME@#$HOME#g; s#@TMUX@#$tmux_bin#g" "$REPO/config/mac/launchd/$label.plist.tmpl" > "$tmp"
    plutil -lint "$tmp" >/dev/null || die "rendered $label plist is invalid"
    changed=0
    cmp -s "$tmp" "$dst" 2>/dev/null || { changed=1; install_file launchd "$tmp" "$dst" 644; }
    [ "$label" = cc-orchestrator.claude.relay ] && [ "$RELAY_CHANGED" = 1 ] && changed=1
    rm -f "$tmp"
    if [ "${CC_INSTALL_NO_LAUNCHD:-0}" = 1 ]; then say launchd "not loading $label (CC_INSTALL_NO_LAUNCHD)"; continue; fi
    launchd_load "$label" "$dst" "$changed"
  done
}

install_mac() {
  [ "$(uname)" = Darwin ] || die "install.sh mac runs on macOS"
  echo "install.sh mac: $REPO → $HOME"
  step_tools; step_bin; step_config; step_tmux; step_claude; step_settings
  step_ntfy; step_zshrc; step_ssh; step_cmux; step_relay; step_launchd
  if [ "$changes" -eq 0 ]; then echo "install.sh mac: no changes"; else echo "install.sh mac: $changes change(s)"; fi
}

# --- cloud-local steps (run on cloud as agent) -------------------------------------------------------
SUDO=${CC_SUDO-sudo}
UNIT_DIR=${CC_UNIT_DIR:-/etc/systemd/system}
RSYSLOG_DIR=${CC_RSYSLOG_DIR:-/etc/rsyslog.d}
LOG_DIR=${CC_LOG_DIR:-/var/log/core}
LEGACY_BIN=${CC_LEGACY_BIN:-/usr/local/bin/fleet}
sudo_() { if [ -n "$SUDO" ]; then "$SUDO" "$@"; else "$@"; fi; }

act() { # act <tag> <description> <cmd…>: run a mutating command, or only report it in a dry run
  local tag=$1 desc=$2; shift 2
  if [ "$DRY" = 1 ]; then did "$tag" "would $desc"; return 0; fi
  "$@"; did "$tag" "$desc"
}

repos_listed() { grep -vE '^[[:space:]]*(#|$)' "$REPO/config/cloud/repos.txt" | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//; s/^[[:space:]]*//' | sort -u; }

step_claude_bin() {
  local c="$HOME/.local/bin/claude"
  if [ -x "$c" ]; then say claude "ok $("$c" --version 2>/dev/null | head -n1)"; return 0; fi
  if [ "${CC_INSTALL_NO_CLAUDE:-0}" = 1 ]; then say claude "missing (CC_INSTALL_NO_CLAUDE set)"; return 0; fi
  # shellcheck disable=SC2016
  act claude "install Claude Code (curl -fsSL https://claude.ai/install.sh | bash)" \
    bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
}

BASHRC_MARK='# cc-orchestrator: ~/.local/bin on PATH, also for non-interactive ssh (managed by install.sh cloud)'
step_path() {
  local b="$HOME/.bashrc" tmp
  if [ -f "$b" ] && grep -qxF "$BASHRC_MARK" "$b"; then say path "ok $b"; return 0; fi
  if [ "$DRY" = 1 ]; then did path "would prepend the PATH line to $b"; return 0; fi
  backup "$b"; tmp=$(mktemp)
  # shellcheck disable=SC2016
  { printf '%s\n%s\n\n' "$BASHRC_MARK" 'case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac'
    [ -f "$b" ] && cat "$b"; } > "$tmp"
  cat "$tmp" > "$b"; rm -f "$tmp"   # keep the inode and mode
  did path "prepended the PATH line to $b (backup .bak.$TS)"
}

BASHRC_SNIPPET_MARK='# cc-orchestrator: ac/am shortcuts (managed by install.sh cloud)'
step_bashrc_snippet() { # appended at the END: after Ubuntu's "not interactive → return", so only interactive shells
  local b="$HOME/.bashrc"
  link config "${LIVE:-$REPO}/config/cloud/bashrc.snippet" "$HOME/.config/cc-orchestrator/bashrc.snippet"
  if [ -f "$b" ] && grep -qxF "$BASHRC_SNIPPET_MARK" "$b"; then say bashrc "ok $b"; return 0; fi
  if [ "$DRY" = 1 ]; then did bashrc "would append the snippet line to $b"; return 0; fi
  backup "$b"
  # shellcheck disable=SC2016
  printf '\n%s\n%s\n' "$BASHRC_SNIPPET_MARK" '[ -r ~/.config/cc-orchestrator/bashrc.snippet ] && . ~/.config/cc-orchestrator/bashrc.snippet' >> "$b"
  did bashrc "appended the snippet line to $b (backup .bak.$TS)"
}

step_config_cloud() {
  local tmp
  tmp=$(mktemp); sed "s#@CC_ORCH_DIR@#${LIVE:-$REPO}#g" "$REPO/config/cloud/config.tmpl" > "$tmp"
  install_file config "$tmp" "$HOME/.config/cc-orchestrator/config" 644; rm -f "$tmp"
}

root_file() { # root_file <tag> <src> <dst>: install a root-owned 0644 file via sudo when different; returns 0 if written
  local tag=$1 src=$2 dst=$3
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then say "$tag" "ok $dst"; return 1; fi
  act "$tag" "install $dst" sudo_ install -m 0644 "$src" "$dst"
}

LEGACY_BAK=${CC_LEGACY_BAK:-$HOME/.local/state/cc-orchestrator/legacy}
step_legacy() { # oci's pre-Phase-4b Claude Code setup (ADR 0002): stop it before any cc-rc@ starts.
  # What is removed is first kept in $LEGACY_BAK, so `./install.sh cloud --rollback` can bring it back.
  local u s before=$changes units
  units=$( { systemctl list-units 'agent@*' --all --plain --no-legend 2>/dev/null
             systemctl list-unit-files 'agent@*' --no-legend 2>/dev/null || true; } | awk '$1 ~ /^agent@.+\.service$/ {print $1}' | sort -u)
  if [ "$DRY" != 1 ] && { [ -n "$units" ] || [ -e "$UNIT_DIR/agent@.service" ] || [ -e "$LEGACY_BIN" ]; }; then
    mkdir -p "$LEGACY_BAK"
    [ -e "$UNIT_DIR/agent@.service" ] && cp "$UNIT_DIR/agent@.service" "$LEGACY_BAK/"
    [ -e "$LEGACY_BIN" ] && cp "$LEGACY_BIN" "$LEGACY_BAK/fleet"
    for u in $units; do grep -qxF "$u" "$LEGACY_BAK/units" 2>/dev/null || echo "$u" >> "$LEGACY_BAK/units"; done
    say legacy "kept a copy in $LEGACY_BAK (for --rollback)"
  fi
  for u in $units; do
    act legacy "stop + disable $u" sudo_ systemctl disable --now "$u"
  done
  for s in "${CC_TMUX_DIR:-/tmp/tmux-$(id -u)}"/agent-*; do
    [ -S "$s" ] || continue
    act legacy "kill tmux server $s" sh -c "tmux -S '$s' kill-server 2>/dev/null; rm -f '$s'"
  done
  [ -e "$UNIT_DIR/agent@.service" ] && act legacy "remove $UNIT_DIR/agent@.service" sudo_ rm -f "$UNIT_DIR/agent@.service"
  [ -e "$LEGACY_BIN" ] && act legacy "remove $LEGACY_BIN (oci fleet CLI; use fleet on the Mac)" sudo_ rm -f "$LEGACY_BIN"
  [ "$changes" -ne "$before" ] || say legacy "ok no agent@ units, agent@.service or $LEGACY_BIN"
}

BROWSER_DIR=${CC_BROWSER_DIR:-$HOME/.local/share/browser-router}
step_browser() { # browser-router (CLI + vault, github.com/<owner>/browser-router) and agent-browser, both from upstream
  local url="https://github.com/${GH_OWNER:-nicolasMazuryk}/browser-router.git" d=$BROWSER_DIR sha stamp="$BROWSER_DIR/.built" ab want
  if [ "${CC_INSTALL_NO_BROWSER:-0}" = 1 ]; then say browser "skipped (CC_INSTALL_NO_BROWSER set)"; return 0; fi
  if [ ! -d "$d/.git" ]; then
    if [ "${CC_INSTALL_NO_CLONE:-0}" = 1 ]; then say browser "missing $d (CC_INSTALL_NO_CLONE set)"; return 0; fi
    act browser "clone $url → $d" git clone -q "$url" "$d"
  elif [ "$DRY" != 1 ] && [ "${CC_INSTALL_NO_CLONE:-0}" != 1 ]; then
    if ! { git -C "$d" fetch -q origin && git -C "$d" merge -q --ff-only '@{u}' 2>/dev/null; }; then
      say browser "WARNING: could not fast-forward $d"
    fi
  fi
  if [ -d "$d/.git" ]; then
    sha=$(git -C "$d" rev-parse HEAD)
    if [ "$(cat "$stamp" 2>/dev/null)" != "$sha" ]; then
      act browser "build browser-router @ ${sha%"${sha#???????}"} (pnpm install --frozen-lockfile; pnpm build)" \
        sh -c "cd '$d' && corepack pnpm install --frozen-lockfile >/dev/null && corepack pnpm build >/dev/null && echo '$sha' > '$stamp'"
    else say browser "ok browser-router built @ ${sha%"${sha#???????}"}"; fi
    link browser "$d/dist/cli.js" "$HOME/.local/bin/browser-router"
  fi
  want=${AGENT_BROWSER_VERSION:-0.39.1}
  ab=$(agent-browser --version 2>/dev/null | head -n1 | awk '{print $NF}' || true)
  if [ "$ab" = "$want" ]; then say browser "ok agent-browser $ab"; return 0; fi
  act browser "install agent-browser@$want (npm -g) + agent-browser install" \
    sh -c "$SUDO npm install -g 'agent-browser@$want' >/dev/null && agent-browser install >/dev/null"
}

step_units() {
  local reload=0 f
  for f in cc-rc@.service cc-agents.service browser-router-vault-drain.service browser-router-vault-drain.timer; do
    root_file units "$REPO/config/cloud/systemd/$f" "$UNIT_DIR/$f" && reload=1
  done
  if [ "$reload" = 1 ] || [ "$changes" -gt 0 ]; then act units "systemctl daemon-reload" sudo_ systemctl daemon-reload; fi
  # the vault drain runs only once browser-router is installed
  if [ -x "$HOME/.local/bin/browser-router" ] || [ -L "$HOME/.local/bin/browser-router" ]; then
    if systemctl is-enabled --quiet browser-router-vault-drain.timer 2>/dev/null; then say units "ok browser-router-vault-drain.timer"
    else act units "enable + start browser-router-vault-drain.timer" sudo_ systemctl enable --now browser-router-vault-drain.timer; fi
  fi
  if [ -d "$RSYSLOG_DIR" ]; then
    if [ ! -e "$LOG_DIR/agent.log" ]; then
      act units "create $LOG_DIR/agent.log" sh -c "$SUDO install -d -m 0755 '$LOG_DIR' && $SUDO install -m 0640 /dev/null '$LOG_DIR/agent.log' && { $SUDO chown syslog:adm '$LOG_DIR/agent.log' 2>/dev/null || true; }"
    fi
    if root_file units "$REPO/config/cloud/rsyslog-cc-orchestrator.conf" "$RSYSLOG_DIR/30-cc-orchestrator.conf"; then
      act units "restart rsyslog" sudo_ systemctl restart rsyslog
    fi
  fi
  return 0
}

step_linger() {
  local u
  u=$(id -un)
  if [ "$(loginctl show-user "$u" -p Linger --value 2>/dev/null)" = yes ]; then say linger "ok $u"; return 0; fi
  act linger "loginctl enable-linger $u" sudo_ loginctl enable-linger "$u"
}

step_repos() {
  local root r
  # shellcheck disable=SC1091
  root=${CC_AGENTS_ROOT:-$(. "$HOME/.config/cc-orchestrator/config" 2>/dev/null; echo "${AGENTS_ROOT:-/data/fleet}")}
  for r in $(repos_listed); do
    if [ ! -d "$root/$r/.git" ]; then
      if [ "${CC_INSTALL_NO_CLONE:-0}" = 1 ]; then say repos "missing $root/$r (CC_INSTALL_NO_CLONE set)"; continue; fi
      act repos "clone github.com/${GH_OWNER:-nicolasMazuryk}/$r → $root/$r" \
        git clone -q "https://github.com/${GH_OWNER:-nicolasMazuryk}/$r.git" "$root/$r"
    fi
    [ "$DRY" = 1 ] && continue
    REPO_INIT_NO_RC=1 "$HOME/.local/bin/repo-init" --no-trust "$root/$r" | grep -E '^  ' | sed "s/^ */  repos     $r: /" || true
  done
  say repos "listed: $(repos_listed | tr '\n' ' ')"
}

step_agents() {
  if systemctl is-enabled --quiet cc-agents 2>/dev/null && systemctl is-active --quiet cc-agents 2>/dev/null; then
    say agents "ok cc-agents (tmux session fleet)"; return 0
  fi
  act agents "enable + start cc-agents" sudo_ systemctl enable --now cc-agents
}

step_rc() {
  local out
  if [ "$DRY" = 1 ]; then
    local r d
    for r in $(repos_listed); do
      d=${CC_AGENTS_ROOT:-/data/fleet}/$r
      if [ ! -d "$d/.git" ]; then say rc "would skip $r (not cloned yet)"
      elif ! jq -e --arg d "$d" '.projects[$d].hasTrustDialogAccepted == true' "$HOME/.claude.json" >/dev/null 2>&1; then
        say rc "would skip $r (workspace not trusted)"
      elif systemctl is-active --quiet "cc-rc@$r"; then say rc "ok cc-rc@$r"
      else did rc "would start cc-rc@$r"; fi
    done
    return 0
  fi
  out=$(CC_SUDO="$SUDO" "$HOME/.local/bin/rc-servers" 2>&1) || true
  if [ -n "$out" ]; then
    printf '%s\n' "$out" | sed 's/^/  rc        /'
    grep -qE '^(started|stopped)' <<<"$out" && changes=$((changes + 1))
  fi
  say rc "cc-rc@: $(systemctl list-units 'cc-rc@*' --plain --no-legend 2>/dev/null | awk '{printf "%s=%s ", $1, $4}')"
}

install_cloud_local() {
  [ "$(uname)" = Linux ] || [ "${CC_INSTALL_ANY_OS:-0}" = 1 ] || die "install.sh cloud-local runs on cloud (Linux)"
  LIVE=${CC_CLOUD_REPO:-$REPO}
  BIN_SKIP="cc-capture cc-sync-settings cc-orchestrator-start agent-relay mac-remote-access browser-up browser-relay-handler"   # Mac-only (they read the Mac's ~/.claude / launchd / browsers)
  echo "install.sh cloud-local: $LIVE → $HOME$([ "$DRY" = 1 ] && echo ' (dry run)')"
  step_claude_bin; step_bin; step_path; step_config_cloud; step_bashrc_snippet; step_tmux
  step_legacy; step_browser; step_units; step_linger; step_repos; step_agents; step_rc
  if [ "$changes" -eq 0 ]; then echo "install.sh cloud-local: no changes"
  else echo "install.sh cloud-local: $changes change(s)$([ "$DRY" = 1 ] && echo ' would be made')"; fi
}

install_cloud_rollback() { # cloud-local-rollback: back to the legacy oci setup kept by step_legacy (tested in bats)
  local u
  [ -f "$LEGACY_BAK/agent@.service" ] || die "no legacy backup in $LEGACY_BAK: nothing to roll back to"
  echo "install.sh cloud-rollback: cc-rc@/cc-agents → legacy agent@ (from $LEGACY_BAK)"
  for u in $({ systemctl list-units 'cc-rc@*' --all --plain --no-legend; systemctl list-unit-files 'cc-rc@*' --state=enabled --no-legend || true; } |
             awk '$1 ~ /^cc-rc@.+\.service$/ {print $1}' | sort -u) cc-agents.service; do
    if systemctl is-active --quiet "$u" || systemctl is-enabled --quiet "$u" 2>/dev/null; then
      act rollback "stop + disable $u" sudo_ systemctl disable --now "$u"
    fi
  done
  for u in cc-rc@.service cc-agents.service; do
    [ -e "$UNIT_DIR/$u" ] && act rollback "remove $UNIT_DIR/$u" sudo_ rm -f "$UNIT_DIR/$u"
  done
  if [ -e "$RSYSLOG_DIR/30-cc-orchestrator.conf" ]; then
    act rollback "remove $RSYSLOG_DIR/30-cc-orchestrator.conf" sudo_ rm -f "$RSYSLOG_DIR/30-cc-orchestrator.conf"
    act rollback "restart rsyslog" sudo_ systemctl restart rsyslog
  fi
  act rollback "restore $UNIT_DIR/agent@.service" sudo_ install -m 0644 "$LEGACY_BAK/agent@.service" "$UNIT_DIR/agent@.service"
  [ -f "$LEGACY_BAK/fleet" ] && act rollback "restore $LEGACY_BIN" sudo_ install -m 0755 "$LEGACY_BAK/fleet" "$LEGACY_BIN"
  act rollback "systemctl daemon-reload" sudo_ systemctl daemon-reload
  while IFS= read -r u; do
    [ -n "$u" ] && act rollback "enable + start $u" sudo_ systemctl enable --now "$u"
  done < "$LEGACY_BAK/units"
  echo "install.sh cloud-rollback: $changes change(s). An oci host-sync with the new bootstrap removes agent@ again:"
  echo "  revert the oci PR first if the legacy setup must stay. Re-migrate with ./install.sh cloud."
}

# --- cloud, from the Mac ------------------------------------------------------------------------------
install_cloud() {
  [ "$(uname)" = Darwin ] || die "install.sh cloud runs on the Mac (it installs on cloud over ssh)"
  local h=${CC_CLOUD_HOST:-cloud} dest out topic rhash lhash dry=0
  [ "${1:-}" = --dry-run ] && dry=1
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$h" true || die "ssh $h failed (Tailscale up? see docs/runbooks/tailscale.md)"
  if [ "${1:-}" = --rollback ]; then
    ssh -o BatchMode=yes "$h" "bash ~/claude-code-fleet/install.sh cloud-local-rollback"; return
  fi
  dest=claude-code-fleet; [ "$dry" = 1 ] && dest=.cache/cc-orchestrator-dryrun
  echo "install.sh cloud: $REPO → $h:~/$dest$([ "$dry" = 1 ] && echo ' (dry run)')"
  out=$(rsync -rlpt --delete -i --exclude=/.git --exclude=/.claude/ --exclude=/tests/ --exclude=/prompts/ --exclude='*.bak.*' --exclude=.DS_Store \
          --filter=':- .gitignore' -e 'ssh -o BatchMode=yes' "$REPO/" "$h:$dest/")
  if [ -n "$out" ]; then
    if [ "$dry" = 1 ]; then say sync "would update ~/claude-code-fleet with:"
    else did sync "updated ~/$dest ($(printf '%s\n' "$out" | wc -l | tr -d ' ') item(s))"; fi
    printf '%s\n' "$out" | sed 's/^/            /'
  else say sync "ok ~/$dest"; fi

  topic="$HOME/.config/agent-push/topic"
  if [ -s "$topic" ]; then
    lhash=$(shasum -a 256 < "$topic" | cut -c1-64)
    rhash=$(ssh -o BatchMode=yes "$h" 'f=~/.config/agent-push/topic; [ -f "$f" ] && sha256sum < "$f" | cut -c1-64' || true)
    if [ "$lhash" = "$rhash" ]; then say ntfy "ok $h:~/.config/agent-push/topic"
    elif [ "$dry" = 1 ]; then did ntfy "would copy the ntfy topic to $h"
    else
      # shellcheck disable=SC2016
      ssh -o BatchMode=yes "$h" 'umask 077; mkdir -p ~/.config/agent-push; cat > ~/.config/agent-push/topic.tmp && mv ~/.config/agent-push/topic.tmp ~/.config/agent-push/topic' < "$topic"
      did ntfy "copied the ntfy topic to $h (0600)"
    fi
  else say ntfy "WARNING: no $topic on the Mac (run ./install.sh mac first); cloud pushes stay off"; fi

  if [ "$dry" = 1 ]; then
    ssh -o BatchMode=yes "$h" "CC_DRY_RUN=1 CC_CLOUD_REPO=\$HOME/claude-code-fleet bash ~/$dest/install.sh cloud-local"
    "$REPO/bin/cc-sync-settings" --dry-run
  else
    ssh -o BatchMode=yes "$h" "bash ~/$dest/install.sh cloud-local"
    "$REPO/bin/cc-sync-settings"
  fi
  echo "install.sh cloud: done (Mac side: $changes change(s)). Checks: docs/runbooks/verify.md §4"
}

case ${1:-} in
  mac) install_mac ;;
  cloud) install_cloud "${2:-}" ;;
  cloud-local) install_cloud_local ;;
  cloud-local-rollback) install_cloud_rollback ;;
  -h|--help) sed -n '2,/^set -e/p' "$0" | sed '$d; s/^# \{0,1\}//' ;;
  *) echo "usage: ./install.sh mac | cloud [--dry-run | --rollback]" >&2; exit 2 ;;
esac
