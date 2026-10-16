#!/usr/bin/env bats
# agent-relay.bats — the Mac side of the cloud sound relay: hash check against the Mac's own settings, rejection of
# malformed/foreign events, no replay of stale events, and one end-to-end run through a fake `ssh cloud`
# (cc-relay-hook on "cloud" → relay → the Mac's handler; presence marker up and down; cloud agent-present).

setup() {
  REPO="$BATS_TEST_DIRNAME/.."
  export HOME="$BATS_TEST_TMPDIR/mac"
  mkdir -p "$HOME/.claude"
  OUT="$BATS_TEST_TMPDIR/handler.out"; LOG="$BATS_TEST_TMPDIR/relay.log"
  # the Mac's own handler: records its stdin (the payload) instead of playing a sound
  CMD="cat >> '$OUT'"
  jq -n --arg c "$CMD" '{hooks: {Stop: [{hooks: [{type: "command", command: $c}]},
                                        {hooks: [{type: "command", command: "~/.claude/hooks/agent-push.sh"}]}]}}' \
    > "$HOME/.claude/settings.json"
  SUM=$(printf %s "$CMD" | shasum -a 256 | cut -c1-16)
  export AGENT_RELAY_SETTINGS="$HOME/.claude/settings.json"
}

ev() { # ev <event> <group> <handler> <sum> [ts] [session]
  jq -nc --arg e "$1" --arg g "$2" --arg h "$3" --arg s "$4" --arg ts "${5:-$(date +%s)}" --arg sid "${6:-sess-1234}" \
    '{event: $e, group: ($g | tonumber? // $g), handler: ($h | tonumber? // $h), sum: $s, ts: ($ts | tonumber),
      payload: {session_id: $sid, hook_event_name: $e}}'
}
relay() { "$REPO/bin/agent-relay" --handle 2>> "$LOG"; }
waitfor() { local i; for i in $(seq 1 50); do eval "$1" && return 0; sleep 0.1; done; return 1; }

@test "matching hash: the Mac's own handler runs with the cloud payload on stdin" {
  ev Stop 0 0 "$SUM" | relay
  waitfor '[ -s "$OUT" ]'
  [ "$(jq -r .session_id "$OUT")" = sess-1234 ]
  grep -q 'ran Stop/0/0 (cloud session sess-123)' "$LOG"
}

@test "changed Mac hook: relay skips and logs, handler does not run" {
  jq '.hooks.Stop[0].hooks[0].command = "afplay /System/Library/Sounds/Ping.aiff"' "$AGENT_RELAY_SETTINGS" > x.json
  mv x.json "$AGENT_RELAY_SETTINGS"
  ev Stop 0 0 "$SUM" | relay
  sleep 0.3; [ ! -e "$OUT" ]
  grep -q 'skipped Stop/0/0: the Mac.s hook changed since the last sync, run cc-sync-settings' "$LOG"
}

@test "wrong hash, missing position or another handler's hash: skipped" {
  { ev Stop 0 0 0123456789abcdef; ev Stop 5 0 "$SUM"; ev Notification 0 0 "$SUM"
    ev Stop 1 0 "$SUM"; } | relay
  sleep 0.3; [ ! -e "$OUT" ]
  [ "$(grep -c 'skipped' "$LOG")" -eq 4 ]
}

@test "malformed or injected fields are ignored; a command sent by cloud is never run" {
  { ev 'Stop;touch /tmp/pwned' 0 0 "$SUM"; ev Stop '0 1' 0 "$SUM"; ev Stop 0 '$(id)' "$SUM"
    ev Stop 0 0 "$SUM; id"; echo 'not json'; echo '{"event":"Stop","group":0,"handler":0}'
    ev Stop 0 0 "$SUM" | jq -c --arg o "$OUT" '.command = "echo pwned > \($o)" | .sum = "ffffffffffffffff"'
  } | relay
  sleep 0.3; [ ! -e "$OUT" ]
  [ "$(grep -c 'ignored malformed event' "$LOG")" -eq 6 ]
  [ "$(grep -c 'skipped' "$LOG")" -eq 1 ]
}

@test "stale events (> AGENT_RELAY_MAX_AGE) are not replayed" {
  ev Stop 0 0 "$SUM" $(( $(date +%s) - 600 )) | relay
  sleep 0.3; [ ! -e "$OUT" ]
  grep -q 'skipped Stop/0/0: 6[0-9][0-9] s old' "$LOG"
}

@test "agent-present on cloud: fresh marker = present, old or missing = away" {
  export AGENT_PRESENT_OS=Linux
  run "$REPO/bin/agent-present"; [ "$status" -eq 1 ]
  mkdir -p "$HOME/.local/state/agent-events"; touch "$HOME/.local/state/agent-events/mac-present"
  run "$REPO/bin/agent-present"; [ "$status" -eq 0 ]
  touch -t "$(date -v-2M +%Y%m%d%H%M.%S 2>/dev/null || date -d '-2 min' +%Y%m%d%H%M.%S)" \
    "$HOME/.local/state/agent-events/mac-present"
  run "$REPO/bin/agent-present"; [ "$status" -eq 1 ]
}

@test "end to end over a fake ssh: cloud event → Mac handler; presence marker follows agent-present" {
  CLOUD="$BATS_TEST_TMPDIR/cloud"; mkdir -p "$CLOUD" "$BATS_TEST_TMPDIR/fake"
  # fake ssh: drop options and the host, run the remote command locally with cloud's HOME
  cat > "$BATS_TEST_TMPDIR/fake/ssh" <<EOF
#!/usr/bin/env bash
while [ \$# -gt 1 ]; do case \$1 in -o) shift 2 ;; *) shift ;; esac; done
HOME="$CLOUD" exec bash -c "\$1"
EOF
  chmod +x "$BATS_TEST_TMPDIR/fake/ssh"
  STATE="$BATS_TEST_TMPDIR/present"; echo 0 > "$STATE"
  printf '#!/bin/sh\nexit $(cat %s)\n' "$STATE" > "$BATS_TEST_TMPDIR/fake/present"; chmod +x "$BATS_TEST_TMPDIR/fake/present"
  AGENT_RELAY_SSH="$BATS_TEST_TMPDIR/fake/ssh" AGENT_PRESENT="$BATS_TEST_TMPDIR/fake/present" \
    AGENT_RELAY_BEACON_SECS=1 "$REPO/bin/agent-relay" 2>> "$LOG" 3>&- &
  pid=$!
  waitfor 'grep -q "connected to cloud" "$LOG"'
  m="$CLOUD/.local/state/agent-events/mac-present"
  waitfor '[ -f "$m" ]'
  HOME="$CLOUD" AGENT_PRESENT_OS=Linux "$REPO/bin/agent-present"
  # a cloud session's Stop hook fires: the stand-in cc-sync-settings wrote into cloud's settings
  echo '{"session_id":"e2e-5678","hook_event_name":"Stop","last_assistant_message":"done"}' |
    HOME="$CLOUD" "$REPO/bin/cc-relay-hook" Stop 0 0 "$SUM"
  waitfor '[ -s "$OUT" ]'
  [ "$(jq -r .session_id "$OUT")" = e2e-5678 ]
  echo 1 > "$STATE"                                   # the Mac goes idle/locked
  waitfor '[ ! -f "$m" ]'
  ! HOME="$CLOUD" AGENT_PRESENT_OS=Linux "$REPO/bin/agent-present"
  kill "$pid"; wait "$pid" || true
  grep -q 'presence: present' "$LOG"; grep -q 'presence: away' "$LOG"
  grep -q 'ran Stop/0/0 (cloud session e2e-5678)' "$LOG"
}
