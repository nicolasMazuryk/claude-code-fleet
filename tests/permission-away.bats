#!/usr/bin/env bats
# permission-away PermissionRequest hook + the mcr-feedback settings delta.

HOOK="$BATS_TEST_DIRNAME/../config/claude/hooks/permission-away"
SETTINGS="$BATS_TEST_DIRNAME/../config/claude/settings.mac.json"
IN='{"session_id":"s1","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"gh pr merge 3"}}'

setup() {
  export PERMISSION_AWAY_LOG="$BATS_TEST_TMPDIR/pa.log"
  export PERMISSION_AWAY_PUSH="$BATS_TEST_TMPDIR/push"
  printf '#!/bin/sh\ncat > "%s/pushed.json"\n' "$BATS_TEST_TMPDIR" > "$PERMISSION_AWAY_PUSH"
  chmod +x "$PERMISSION_AWAY_PUSH"
}

@test "away: denies with a Human away message naming the tool" {
  run bash -c "echo '$IN' | AGENT_PRESENT=false '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(jq -r .hookSpecificOutput.hookEventName <<<"$output")" = PermissionRequest ]
  [ "$(jq -r .hookSpecificOutput.decision.behavior <<<"$output")" = deny ]
  jq -r .hookSpecificOutput.decision.message <<<"$output" | grep -q '^Human away: approval needed for Bash: gh pr merge 3'
  jq -r .hookSpecificOutput.decision.message <<<"$output" | grep -q 'needs-approval'
}

@test "away: pushes a needs-input notification and logs" {
  echo "$IN" | AGENT_PRESENT=false "$HOOK" >/dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$BATS_TEST_TMPDIR/pushed.json" ] && break; sleep 0.2; done
  [ "$(jq -r .notification_type "$BATS_TEST_TMPDIR/pushed.json")" = agent_needs_input ]
  grep -q 'denied-away Bash' "$PERMISSION_AWAY_LOG"
}

@test "present: prints nothing (normal prompt)" {
  run bash -c "echo '$IN' | AGENT_PRESENT=true '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "bad input: prints nothing, exits 0" {
  run bash -c "echo 'not json' | AGENT_PRESENT=false '$HOOK'"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run bash -c "AGENT_PRESENT=false '$HOOK' </dev/null"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "settings: PermissionRequest registers permission-away" {
  jq -e '[.hooks.PermissionRequest[].hooks[].command] | index("~/.claude/hooks/permission-away")' "$SETTINGS"
}

@test "settings: no public-repo deny, merge allowed without a CI condition" {
  [ "$(jq '[.permissions.deny[] | select(test("public"))] | length' "$SETTINGS")" -eq 0 ]
  [ "$(jq '[.autoMode.hard_deny[] | select(test("public"))] | length' "$SETTINGS")" -eq 0 ]
  jq -e '.autoMode.allow | index("Merging the user'"'"'s own pull requests on github.com/nicolasMazuryk repos is allowed.")' "$SETTINGS"
}

@test "settings: SIP deny floor lists mutations only; status reads reachable" {
  for r in 'Bash(csrutil *)' 'Bash(tccutil *)' 'Bash(nvram *)' 'Bash(fdesetup *)'; do
    [ "$(jq --arg r "$r" '.permissions.deny | index([$r])' "$SETTINGS")" = null ] || { echo "still denied: $r"; return 1; }
  done
  jq -e '.permissions.deny | index(["Bash(csrutil disable*)"])' "$SETTINGS"
  jq -e '.permissions.deny | index(["Bash(sudo *)"])' "$SETTINGS"
}

@test "settings: GUI allows for mac-control-router" {
  for r in 'Bash(open -a *)' 'Bash(killall Dock)' 'Bash(defaults write com.apple.dock *)' 'Bash(cliclick *)'; do
    jq -e --arg r "$r" '.permissions.allow | index([$r])' "$SETTINGS" >/dev/null || { echo "missing allow: $r"; return 1; }
  done
}
