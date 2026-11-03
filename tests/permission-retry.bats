#!/usr/bin/env bats
# permission-retry PermissionDenied hook + the J3 settings delta.

HOOK="$BATS_TEST_DIRNAME/../config/claude/hooks/permission-retry"
SETTINGS="$BATS_TEST_DIRNAME/../config/claude/settings.mac.json"
MACONLY="$BATS_TEST_DIRNAME/../config/claude/mac-only.json"
RETRY='{"hookSpecificOutput":{"hookEventName":"PermissionDenied","retry":true}}'
PB=mcp__plugin_mac-control-router_peekaboo__

bash_in() { jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | "$HOOK"; }
mcp_in() { jq -nc --arg t "$1" --arg a "$2" '{tool_name:$t,tool_input:(if $a=="" then {} else {action:$a} end)}' | "$HOOK"; }

@test "read-only Bash probes retry" {
  for c in "peekaboo see --app Finder" "peekaboo list apps" "peekaboo window list --app X" \
    "peekaboo menu list --app X" "defaults read com.apple.finder" "lsappinfo list" "lsappinfo front" \
    "lsappinfo info -only name 1234" "lsappinfo find name=Finder" "lsappinfo visibleProcessList" \
    "lsappinfo processList" "mdfind -name foo"; do
    run bash_in "$c"
    [ "$status" -eq 0 ]
    [ "$output" = "$RETRY" ] || { echo "no retry: $c"; return 1; }
  done
}

@test "read-only MCP probes retry" {
  run mcp_in "${PB}see" ""; [ "$output" = "$RETRY" ]
  run mcp_in "${PB}window" list; [ "$output" = "$RETRY" ]
  run mcp_in "${PB}menu" list; [ "$output" = "$RETRY" ]
}

@test "mutating or unknown Bash stays silent" {
  for c in "peekaboo click --id B1" "peekaboo type hi" "peekaboo app quit --app X" "peekaboo window close" \
    "defaults write com.apple.finder x 1" "rm -rf x" "make apply-x" "lsappinfo setinfo x" "lsappinfo" "ls"; do
    run bash_in "$c"
    [ "$status" -eq 0 ]
    [ -z "$output" ] || { echo "retry on: $c"; return 1; }
  done
}

@test "chained or metacharacter Bash stays silent" {
  for c in "peekaboo see; rm x" 'peekaboo see $(rm x)' "peekaboo see > f" "peekaboo see | tee f" \
    "peekaboo see && rm x" 'peekaboo see `id`' "mdfind x < f" "$(printf 'peekaboo see\nrm x')"; do
    run bash_in "$c"
    [ "$status" -eq 0 ]
    [ -z "$output" ] || { echo "retry on: $c"; return 1; }
  done
}

@test "MCP mutating actions and other tools stay silent" {
  for a in close move click; do
    run mcp_in "${PB}window" "$a"; [ -z "$output" ]
  done
  run mcp_in "${PB}menu" click; [ -z "$output" ]
  run mcp_in "${PB}window" ""; [ -z "$output" ]
  run mcp_in "${PB}click" list; [ -z "$output" ]
  run mcp_in "mcp__other__see" ""; [ -z "$output" ]
}

@test "malformed, empty and non-Bash input stay silent with exit 0" {
  run bash -c "printf 'not json' | '$HOOK'"; [ "$status" -eq 0 ]; [ -z "$output" ]
  run bash -c "printf '' | '$HOOK'"; [ "$status" -eq 0 ]; [ -z "$output" ]
  run bash -c "echo '{\"tool_name\":\"Read\",\"tool_input\":{\"command\":\"peekaboo see\"}}' | '$HOOK'"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "script keeps Mac-only trigger words out (no relay stub)" {
  run grep -E 'afplay|osascript|terminal-notifier|say' "$HOOK"
  [ "$status" -eq 1 ]
}

@test "settings: new allow/deny entries, make apply-* gone" {
  jq -e '.permissions.allow | index("Bash(sleep *)") and index("Bash(open -g x-apple.systempreferences:*)") and index("Bash(make host-sync*)")' "$SETTINGS"
  jq -e '.permissions.allow | index("Bash(make apply-*)") | not' "$SETTINGS"
  for p in '*:main*' '*:master*' '*:refs/heads/main*' '*:refs/heads/master*'; do
    jq -e --arg d "Bash(git push * $p)" '.permissions.deny | index($d)' "$SETTINGS"
  done
}

@test "settings: PermissionDenied hook wired; no browser-guard or onFailure in settings (the browser-router plugin owns them)" {
  jq -e '.hooks.PermissionDenied[0].hooks[0].command == "~/.claude/hooks/permission-retry"' "$SETTINGS"
  [ "$(jq '[.. | objects | select(has("onFailure"))] | length' "$SETTINGS")" = "0" ]
  [ "$(jq '[.. | objects | select((.command // "") | test("browser-guard"))] | length' "$SETTINGS")" = "0" ]
  jq -e '.enabledPlugins["browser-router@browser-router"] == true' "$SETTINGS"
}

@test "mac-only takes the plugin's permission rules (incl. the system-settings open) from its template" {
  jq -e '.permissionFiles | index("mac-control-router/setup/user-settings.json")' "$MACONLY"
}
