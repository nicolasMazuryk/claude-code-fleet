#!/usr/bin/env bats
# agent-push.bats — push gating table of hooks/agent-push.sh (presence, event types, subagents, background jobs).

setup() {
  HOOK="$BATS_TEST_DIRNAME/../hooks/agent-push.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.config/agent-push"
  echo 0123456789abcdef0123456789abcdef > "$HOME/.config/agent-push/topic"
  LOG="$BATS_TEST_TMPDIR/curl.log"; : > "$LOG"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s"\n' "$LOG" > "$BATS_TEST_TMPDIR/curl"
  chmod +x "$BATS_TEST_TMPDIR/curl"
  export AGENT_PUSH_CURL="$BATS_TEST_TMPDIR/curl" AGENT_PRESENT=false AGENT_HOST=mac
  unset CLAUDE_JOB_DIR CLAUDE_CODE_BRIDGE_SESSION_ID
}

push() { printf '%s' "$1" | "$HOOK"; }
pushed() { [ -s "$LOG" ]; }

@test "present at the Mac: no push" {
  AGENT_PRESENT=true push '{"hook_event_name":"Stop"}'
  ! pushed
}

@test "away + Stop of an interactive session: push 'done'" {
  push '{"hook_event_name":"Stop","last_assistant_message":"all green"}'
  pushed; grep -q 'Title: mac · done' "$LOG"; grep -q 'all green' "$LOG"
}

@test "away + permission prompt: high-priority 'needs input'" {
  push '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Allow Bash?"}'
  grep -q 'Priority: high' "$LOG"; grep -q 'needs input' "$LOG"
}

@test "away + agent_needs_input from Agent View: push even with CLAUDE_JOB_DIR" {
  CLAUDE_JOB_DIR=/x push '{"hook_event_name":"Notification","notification_type":"agent_needs_input"}'
  pushed
}

@test "background session's own Stop: no push (Agent View reports it)" {
  CLAUDE_JOB_DIR=/x push '{"hook_event_name":"Stop"}'
  ! pushed
}

@test "subagent events and other notification types: no push" {
  push '{"hook_event_name":"Stop","agent_id":"a1"}'
  push '{"hook_event_name":"Notification","notification_type":"idle_prompt"}'
  ! pushed
}

@test "bridge session id adds a Click header" {
  CLAUDE_CODE_BRIDGE_SESSION_ID=abc push '{"hook_event_name":"Stop"}'
  grep -q 'Click: https://claude.ai/code/abc' "$LOG"
}

@test "no topic file: no push, exit 0" {
  rm "$HOME/.config/agent-push/topic"
  run push '{"hook_event_name":"Stop"}'
  [ "$status" -eq 0 ]; ! pushed
}
