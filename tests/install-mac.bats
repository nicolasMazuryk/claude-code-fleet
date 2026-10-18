#!/usr/bin/env bats
# install-mac.bats — ./install.sh mac against a scratch HOME: settings merge, hook append, idempotence, backups.

setup() {
  REPO="$BATS_TEST_DIRNAME/.."
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude" "$HOME/.ssh" "$HOME/.config/cmux"
  cp "$REPO/config/claude/settings.mac.json" "$HOME/.claude/settings.json"
  # the live Mac before Phase 3: both notif flags on, no remoteControlAtStartup
  jq '.inputNeededNotifEnabled = true | .agentPushNotifEnabled = true | del(.remoteControlAtStartup)
      | .env = {"KEEP_ME": "1"}' "$HOME/.claude/settings.json" > "$HOME/s" && mv "$HOME/s" "$HOME/.claude/settings.json"
  printf 'alias c=claude\n' > "$HOME/.zshrc"
  printf 'Host *\n  AddKeysToAgent yes\n' > "$HOME/.ssh/config"
  printf '{\n  "$schema": "x",\n  "schemaVersion": 1,\n\n  // "app" : {\n  //   "x" : 1\n  // },\n}\n' > "$HOME/.config/cmux/cmux.json"
  export CC_INSTALL_NO_BREW=1 CC_INSTALL_NO_LAUNCHD=1 CC_INSTALL_NO_VAULT=1
}

@test "first run merges orchestrator keys and appends agent-push once, keeping the 4 sound hooks" {
  run "$REPO/install.sh" mac
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  s="$HOME/.claude/settings.json"
  [ "$(jq -r .remoteControlAtStartup "$s")" = true ]
  [ "$(jq -r .inputNeededNotifEnabled "$s")" = false ]
  [ "$(jq -r .agentPushNotifEnabled "$s")" = false ]
  [ "$(jq -r .env.CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX "$s")" = mac ]
  [ "$(jq -r .env.KEEP_ME "$s")" = 1 ]
  [ "$(jq '[.hooks[][].hooks[] | select(.command | test("afplay"))] | length' "$s")" -eq 4 ]
  [ "$(jq '[.hooks[][].hooks[] | select(.command | test("agent-push"))] | length' "$s")" -eq 2 ]
  # appended after the existing groups (relay positions unchanged)
  [ "$(jq -r '.hooks.Notification[-1].hooks[0].command' "$s")" = "~/.claude/hooks/agent-push.sh" ]
  [ "$(jq -r '.hooks.Stop[0].hooks[0].command' "$s")" != "~/.claude/hooks/agent-push.sh" ]
  [ "$(jq -r '.hooks.Stop[-1].hooks[0].async' "$s")" = true ]
  ls "$s".bak.* >/dev/null
}

@test "files, links, topic, zshrc, ssh and cmux are installed" {
  run "$REPO/install.sh" mac
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(readlink "$HOME/.local/bin/rc-servers")" = "$(cd "$REPO" && pwd)/bin/rc-servers" ]
  grep -qx 'AGENT_HOST=mac' "$HOME/.config/cc-orchestrator/config"
  grep -q "CC_ORCH_DIR=\"$(cd "$REPO" && pwd)\"" "$HOME/.config/cc-orchestrator/config"
  [ -x "$HOME/.claude/hooks/agent-push.sh" ]
  cmp "$REPO/config/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  cmp "$REPO/config/mac/tmux.conf" "$HOME/.tmux.conf"
  [ "$(stat -f %Lp "$HOME/.config/agent-push/topic")" = 600 ]
  grep -qE '^[0-9a-f]{32}$' "$HOME/.config/agent-push/topic"
  [ "$(grep -c 'zshrc.snippet' "$HOME/.zshrc")" -eq 1 ]
  # a regular file (phone ssh/mosh shells can't follow a link into ~/Documents)
  [ -f "$HOME/.config/cc-orchestrator/zshrc.snippet" ] && [ ! -L "$HOME/.config/cc-orchestrator/zshrc.snippet" ]
  cmp "$REPO/config/mac/zshrc.snippet" "$HOME/.config/cc-orchestrator/zshrc.snippet"
  grep -qx 'alias c=claude' "$HOME/.zshrc"
  grep -qx 'Host cloud' "$HOME/.ssh/config"
  grep -qx '  User agent' "$HOME/.ssh/config"
  cmp "$REPO/config/mac/cmux.json" "$HOME/.config/cmux/cmux.json"
  [ -f "$HOME/Library/LaunchAgents/cc-orchestrator.claude.agents.plist" ]
  # relay: runs copies outside ~/Documents (TCC), plist points at them
  cmp "$REPO/bin/agent-relay" "$HOME/.local/libexec/cc-orchestrator/agent-relay"
  cmp "$REPO/bin/agent-present" "$HOME/.local/libexec/cc-orchestrator/agent-present"
  [ -x "$HOME/.local/libexec/cc-orchestrator/agent-relay" ]
  grep -q "<string>$HOME/.local/libexec/cc-orchestrator/agent-relay</string>" \
    "$HOME/Library/LaunchAgents/cc-orchestrator.claude.relay.plist"
  grep -q "$HOME/.local/bin/cc-orchestrator-start" "$HOME/Library/LaunchAgents/cc-orchestrator.claude.agents.plist"
}

@test "second run changes nothing and makes no new backups" {
  "$REPO/install.sh" mac >/dev/null
  before=$(find "$HOME" -name '*.bak.*' | wc -l)
  topic=$(cat "$HOME/.config/agent-push/topic")
  sleep 1
  run "$REPO/install.sh" mac
  [ "$status" -eq 0 ]
  [[ "$output" == *"install.sh mac: no changes"* ]] || { echo "$output"; return 1; }
  [ "$(find "$HOME" -name '*.bak.*' | wc -l)" -eq "$before" ]
  [ "$(cat "$HOME/.config/agent-push/topic")" = "$topic" ]
}

@test "a cmux.json with real settings and an existing Host cloud are left alone" {
  printf '{ "app": { "confirmQuit": "never" } }\n' > "$HOME/.config/cmux/cmux.json"
  printf 'Host cloud\n  User someone\n' >> "$HOME/.ssh/config"
  run "$REPO/install.sh" mac
  [ "$status" -eq 0 ]
  grep -q never "$HOME/.config/cmux/cmux.json"
  [ "$(grep -c 'Host cloud' "$HOME/.ssh/config")" -eq 1 ]
}

@test "invalid settings.json aborts without writing" {
  echo '{ broken' > "$HOME/.claude/settings.json"
  run "$REPO/install.sh" mac
  [ "$status" -ne 0 ]
  [ "$(cat "$HOME/.claude/settings.json")" = '{ broken' ]
}

@test "missing settings.json is seeded from the captured baseline" {
  rm "$HOME/.claude/settings.json"
  run "$REPO/install.sh" mac
  [ "$status" -eq 0 ]
  [ "$(jq '[.hooks[][].hooks[] | select(.command | test("afplay"))] | length' "$HOME/.claude/settings.json")" -eq 4 ]
  [ "$(jq -r .remoteControlAtStartup "$HOME/.claude/settings.json")" = true ]
}

@test "profile and project memories are restored from config/ only where missing" {
  c="$REPO/config/claude"
  [ -f "$c/profile/me.md" ] && [ -n "$(ls "$c/memory")" ]
  m=$(ls "$c/memory" | head -1)
  mkdir -p "$HOME/.claude/profile" && echo 'local edit' > "$HOME/.claude/profile/me.md"
  run "$REPO/install.sh" mac
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$HOME/.claude/profile/me.md")" = 'local edit' ]
  cmp "$c/profile/goals.md" "$HOME/.claude/profile/goals.md"
  diff -r "$c/memory/$m" "$HOME/.claude/projects/$m/memory"
}
