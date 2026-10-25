#!/usr/bin/env bats
# session-env.bats — hooks/session-env.sh: SessionStart payload session_id → CLAUDE_SESSION_ID in CLAUDE_ENV_FILE.

setup() {
  H="$BATS_TEST_DIRNAME/../hooks/session-env.sh"
  export CLAUDE_ENV_FILE="$BATS_TEST_TMPDIR/env"
  : > "$CLAUDE_ENV_FILE"
}

@test "writes the export for every source" {
  for src in startup resume clear compact fork; do
    : > "$CLAUDE_ENV_FILE"
    run "$H" <<<"{\"session_id\":\"0fe4247b-1c2d-4e5f-8a9b-0c1d2e3f4a5b\",\"source\":\"$src\",\"hook_event_name\":\"SessionStart\"}"
    [ "$status" -eq 0 ]
    [ "$(cat "$CLAUDE_ENV_FILE")" = 'export CLAUDE_SESSION_ID=0fe4247b-1c2d-4e5f-8a9b-0c1d2e3f4a5b' ]
  done
}

@test "appends: other hooks' lines survive, and the sourced file sets the variable" {
  echo 'export OTHER=1' > "$CLAUDE_ENV_FILE"
  run "$H" <<<'{"hook_event_name":"SessionStart","session_id":"abc-123"}'
  [ "$status" -eq 0 ]
  run bash -c '. "$CLAUDE_ENV_FILE"; echo "$OTHER $CLAUDE_SESSION_ID"'
  [ "$output" = '1 abc-123' ]
}

@test "multi-line pretty-printed payload" {
  run "$H" <<<$'{\n  "session_id": "abc-123",\n  "source": "resume"\n}'
  [ "$(cat "$CLAUDE_ENV_FILE")" = 'export CLAUDE_SESSION_ID=abc-123' ]
}

@test "rejects ids outside [A-Za-z0-9-] and writes nothing" {
  for bad in 'a;rm -rf x' 'a$(id)' 'a b' 'a`id`' 'a_b' ''; do
    run "$H" <<<"{\"session_id\":\"$bad\"}"
    [ "$status" -eq 0 ]
    [ ! -s "$CLAUDE_ENV_FILE" ]
  done
}

@test "no session_id, empty or garbage stdin, or no CLAUDE_ENV_FILE: exit 0, nothing written" {
  run "$H" <<<'{"source":"startup"}'; [ "$status" -eq 0 ]
  run "$H" <<<''; [ "$status" -eq 0 ]
  run "$H" <<<'not json'; [ "$status" -eq 0 ]
  [ ! -s "$CLAUDE_ENV_FILE" ]
  unset CLAUDE_ENV_FILE
  run "$H" <<<'{"session_id":"abc"}'; [ "$status" -eq 0 ]
}
