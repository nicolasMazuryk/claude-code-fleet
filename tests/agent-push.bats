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
  grep -q 'pushed "done" (with Click)' "$HOME/.local/state/agent-push/push.log"
}

@test "no bridge session id: Click opens the Claude app's Code tab" {
  push '{"hook_event_name":"Stop"}'
  grep -qx 'Click: https://claude.ai/code' "$LOG"
  grep -q 'pushed "done" (Click: Code tab)' "$HOME/.local/state/agent-push/push.log"
}

@test "no topic file: no push, exit 0" {
  rm "$HOME/.config/agent-push/topic"
  run push '{"hook_event_name":"Stop"}'
  [ "$status" -eq 0 ]; ! pushed
}

@test "every decision is logged with CLAUDE_JOB_DIR status; the topic never is" {
  AGENT_PRESENT=true push '{"hook_event_name":"Stop"}'
  CLAUDE_JOB_DIR=/x push '{"hook_event_name":"Stop"}'
  push '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Allow?"}'
  L="$HOME/.local/state/agent-push/push.log"
  grep -q 'Stop:- job=unset present: no push' "$L"
  grep -q 'Stop:- job=set background session: no push' "$L"
  grep -q 'Notification:permission_prompt job=unset pushed "needs input"' "$L"
  ! grep -q 0123456789abcdef "$L"; ! grep -q 'Allow?' "$L"
}

@test "the topic is passed in a curl config, never in argv" {
  push '{"hook_event_name":"Stop"}'
  pushed; ! grep -q 0123456789abcdef "$LOG"
}

@test "real curl reads the URL from the config fd (local ntfy stand-in)" {
  command -v python3 >/dev/null || skip "no python3"
  port=$((20000 + RANDOM % 20000)); got="$BATS_TEST_TMPDIR/got"
  python3 -c '
import http.server,sys
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(s):
        n=int(s.headers["Content-Length"]); b=s.rfile.read(n)
        open(sys.argv[2],"w").write(s.path+" "+s.headers["Title"]+" "+b.decode())
        s.send_response(200); s.end_headers()
    def log_message(s,*a): pass
http.server.HTTPServer(("127.0.0.1",int(sys.argv[1])),H).handle_request()' "$port" "$got" 3>&- &
  sleep 0.5
  AGENT_PUSH_CURL=curl NTFY_SERVER="http://127.0.0.1:$port" push '{"hook_event_name":"Stop","last_assistant_message":"ok"}'
  wait
  [ "$(cut -d' ' -f1 "$got")" = /0123456789abcdef0123456789abcdef ]   # URL path = topic, read from the config
  grep -q ' done ok' "$got"
}

@test "curl failure is logged, still exit 0" {
  AGENT_PUSH_CURL=false run push '{"hook_event_name":"Stop"}'
  [ "$status" -eq 0 ]
  grep -q 'push "done" FAILED' "$HOME/.local/state/agent-push/push.log"
}
