#!/usr/bin/env bash
# install.sh mac | cloud — install cc-orchestrator on this host. Idempotent: a second run changes nothing.
#
#   ./install.sh mac     (run on the Mac, from the checkout that should be live; usually ~/Documents/cc-orchestrator)
#   ./install.sh cloud   Phase 4
#
# mac, in order (each step prints "ok" when already in place, "updated"/"created" when it wrote something):
#   tools       brew install tmux mosh if missing
#   bin         ~/.local/bin/<script> → <repo>/bin/<script> (symlinks; editing the repo changes what runs)
#   config      ~/.config/cc-orchestrator/config (from config/mac/config.tmpl), zshrc.snippet symlink
#   tmux        ~/.tmux.conf
#   claude      ~/.claude/CLAUDE.md, statusline-combined.sh (node path fix), hooks/agent-push.sh;
#               baseline files from config/claude/ only where missing (sounds, skills, claude-hud, ccstatusline)
#   settings    ~/.claude/settings.json: seeded from settings.mac.json if absent; settings.orchestrator.json
#               deep-merged; one agent-push.sh group appended to Notification and Stop (once). Backup first.
#   ntfy        ~/.config/agent-push/topic (0600): kept if present, else Vault core-secret-ntfy-topic, else new
#   zshrc       one sourcing line for the snippet (am, ac); existing aliases untouched
#   ssh         Host cloud appended to ~/.ssh/config if no Host cloud exists
#   cmux        ~/.config/cmux/cmux.json if absent or still cmux's all-comments template
#   launchd     cc-orchestrator.claude.agents (+ .relay once bin/agent-relay exists, Phase 5), bootstrapped
#
# Every overwritten user file is backed up first as <file>.bak.<timestamp>.
# Test/CI switches: CC_INSTALL_NO_BREW=1, CC_INSTALL_NO_LAUNCHD=1, CC_INSTALL_NO_VAULT=1 (HOME may be a scratch dir).
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
TS=$(date +%Y%m%d-%H%M%S)
changes=0

say() { printf '  %-9s %s\n' "$1" "$2"; }
did() { changes=$((changes + 1)); say "$1" "$2"; }
die() { echo "install.sh: $*" >&2; exit 1; }

backup() { # backup <file>: copy to <file>.bak.<ts> if it exists (regular file or symlink)
  if [ -e "$1" ] || [ -L "$1" ]; then cp -pP "$1" "$1.bak.$TS"; fi
}

install_file() { # install_file <tag> <src> <dst> <mode>: copy if different, backing up the old one
  local tag=$1 src=$2 dst=$3 mode=$4
  if [ -f "$dst" ] && [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then
    say "$tag" "ok $dst"; return 0
  fi
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

step_bin() {
  local f n before=$changes
  for f in "$REPO"/bin/*; do
    n=$(basename "$f")
    [ -x "$f" ] && [ -f "$f" ] || continue
    link bin "$f" "$HOME/.local/bin/$n"
  done
  # drop links into a cc-orchestrator bin/ whose script no longer exists here
  for f in "$HOME"/.local/bin/*; do
    [ -L "$f" ] || continue
    case $(readlink "$f") in
      */cc-orchestrator*/bin/*) [ -e "$REPO/bin/$(basename "$f")" ] || { rm -f "$f"; did bin "removed stale $f"; } ;;
    esac
  done
  [ "$changes" -ne "$before" ] || say bin "ok ~/.local/bin → $REPO/bin"
}

step_config() {
  local tmp
  tmp=$(mktemp); sed "s#@CC_ORCH_DIR@#$REPO#g" "$REPO/config/mac/config.tmpl" > "$tmp"
  install_file config "$tmp" "$HOME/.config/cc-orchestrator/config" 644; rm -f "$tmp"
  link config "$REPO/config/mac/zshrc.snippet" "$HOME/.config/cc-orchestrator/zshrc.snippet"
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
  return 0
}

# shellcheck disable=SC2016
SETTINGS_JQ='
  def addpush($ev):
    .hooks[$ev] = ((.hooks[$ev] // []) as $g
      | if any($g[]?.hooks[]?; (.command // "") | test("agent-push\\.sh")) then $g
        else $g + [{hooks: [{type: "command", command: "~/.claude/hooks/agent-push.sh", async: true}]}] end);
  (.[0] * .[1]) | addpush("Notification") | addpush("Stop")'

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

step_launchd() {
  local la="$HOME/Library/LaunchAgents" label tmp dst changed
  for label in cc-orchestrator.claude.agents cc-orchestrator.claude.relay; do
    if [ "$label" = cc-orchestrator.claude.relay ] && [ ! -x "$REPO/bin/agent-relay" ]; then
      say launchd "skip $label (bin/agent-relay arrives in Phase 5)"; continue
    fi
    dst="$la/$label.plist"; tmp=$(mktemp)
    sed "s#@HOME@#$HOME#g" "$REPO/config/mac/launchd/$label.plist.tmpl" > "$tmp"
    plutil -lint "$tmp" >/dev/null || die "rendered $label plist is invalid"
    changed=0
    cmp -s "$tmp" "$dst" 2>/dev/null || { changed=1; install_file launchd "$tmp" "$dst" 644; }
    rm -f "$tmp"
    if [ "${CC_INSTALL_NO_LAUNCHD:-0}" = 1 ]; then say launchd "not loading $label (CC_INSTALL_NO_LAUNCHD)"; continue; fi
    launchd_load "$label" "$dst" "$changed"
  done
}

install_mac() {
  [ "$(uname)" = Darwin ] || die "install.sh mac runs on macOS"
  echo "install.sh mac: $REPO → $HOME"
  step_tools; step_bin; step_config; step_tmux; step_claude; step_settings
  step_ntfy; step_zshrc; step_ssh; step_cmux; step_launchd
  if [ "$changes" -eq 0 ]; then echo "install.sh mac: no changes"; else echo "install.sh mac: $changes change(s)"; fi
}

case ${1:-} in
  mac) install_mac ;;
  cloud) echo "install.sh cloud: not implemented yet (Phase 4); see prompts/plan.md" >&2; exit 2 ;;
  -h|--help) sed -n '2,/^set -e/p' "$0" | sed '$d; s/^# \{0,1\}//' ;;
  *) echo "usage: ./install.sh mac | cloud" >&2; exit 2 ;;
esac
