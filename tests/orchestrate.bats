#!/usr/bin/env bats
# orchestrate.bats — orchestrate skill scripts against a scratch $HOME and run dir: orchestrator-plan reads synthetic
# planner transcripts, orchestrator-set-status validates states, orchestrator-recontext prints per-role context.

setup() {
  S="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/config/claude/skills/orchestrate/scripts"
  export HOME="$BATS_TEST_TMPDIR/home"
  R="$BATS_TEST_TMPDIR/run"; P="$HOME/.claude/projects/p"
  mkdir -p "$P" "$R/jobs/P-J1"
  printf '{"job":"P-J1","session_id":"s1"}\n' > "$R/jobs/P-J1/status.json"
  EXIT='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"ExitPlanMode","input":{"plan":"# Plan\nstep 1","planFilePath":"/x"}}]}}'
  ASK='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"AskUserQuestion","input":{"questions":[{"question":"Which DB?","header":"db","multiSelect":false,"options":[{"label":"pg"},{"label":"sqlite"}]}]}}]}}'
  RESULT='{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"rejected"}]}}'
}

transcript() { printf '%s\n' "$@" > "$P/s1.jsonl"; }

@test "orchestrator-plan: pending ExitPlanMode is ready and writes plan.md" {
  transcript '{"type":"user","message":{"content":"go"}}' "$EXIT"
  run "$S/orchestrator-plan" "$R" J1
  [ "$status" -eq 0 ]
  [ "$output" = "ready $R/jobs/J1/plan.md" ]
  [ "$(cat "$R/jobs/J1/plan.md")" = "$(printf '# Plan\nstep 1')" ]
  run "$S/orchestrator-plan" "$R" P-J1
  [ "${lines[0]}" = "ready $R/jobs/J1/plan.md" ]
}

@test "orchestrator-plan: pending AskUserQuestion is asking with the question" {
  transcript "$ASK"
  run "$S/orchestrator-plan" "$R" J1
  [ "${lines[0]}" = asking ]
  [ "${lines[1]}" = "- Which DB? [pg | sqlite]" ]
}

@test "orchestrator-plan: answered ExitPlanMode is none and writes nothing" {
  transcript "$EXIT" "$RESULT"
  run "$S/orchestrator-plan" "$R" J1
  [ "$output" = none ]
  [ ! -e "$R/jobs/J1/plan.md" ]
}

@test "orchestrator-plan: no transcript is none" {
  run "$S/orchestrator-plan" "$R" J1
  [ "$output" = none ]
}

@test "orchestrator-set-status: accepts plan states, rejects unknown ones" {
  for st in planning plan_ready plan_approved; do
    run "$S/orchestrator-set-status" "$R" J1 "$st" x
    [ "$status" -eq 0 ]
    [ "$(jq -r .state "$R/jobs/J1/status.json")" = "$st" ]
  done
  run "$S/orchestrator-set-status" "$R" J1 bogus x
  [ "$status" -eq 2 ]
}

@test "orchestrator-recontext: planner, plan review and implementer context; valid --settings JSON" {
  run "$S/orchestrator-recontext" "$R" P-J1
  [[ $output == *"planner P-J1"*"ExitPlanMode"* ]]
  run "$S/orchestrator-recontext" "$R" PV-J1
  [[ $output == *"verifier PV-J1 in plan-review mode"* ]]
  mkdir -p "$R/jobs/J1"; echo "# approved" > "$R/jobs/J1/plan.md"
  run "$S/orchestrator-recontext" "$R" J1
  [[ $output == *"implementer J1"*"### plan.md (approved plan)"*"# approved"* ]]
  for j in P-J1 PV-J1 J1; do
    "$S/orchestrator-recontext" --settings "$R" "$j" | jq -e '.hooks.SessionStart[0].matcher == "compact"'
  done
}

# orchestrator-cleanup against a stub claude: argv → $CL/calls; `agents` prints $CL/agents.json; `stop` clears the pid;
# `rm` drops the row unless its id is listed in $CL/rm-fail
cleanup_setup() {
  CL="$BATS_TEST_TMPDIR/claude"; mkdir -p "$CL" "$BATS_TEST_TMPDIR/bin"; : > "$CL/calls"; : > "$CL/rm-fail"
  cp "$BATS_TEST_DIRNAME/fakes/claude" "$BATS_TEST_TMPDIR/bin/claude"
  export FAKE_CLAUDE="$CL" PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  slug=$(basename "$R")
  row() { jq -n -c --arg n "$slug-$1" --arg i "$2" --arg s "$3" --argjson p "$4" \
    '{name: $n, id: $i, sessionId: ("sid-" + $i), state: $s, status: null, pid: $p, waitingFor: null}'; }
  { row orchestrator o0000000 working 10; row J1 a1111111 done 11; row J1-r1 a2222222 done null
    row P-J1 b1111111 stopped null; row PV-J1 c1111111 done null; row V-J1-r2 d1111111 done 12
    row J2 e1111111 working 13; row P-J2 f1111111 stopped null; row J10 g1111111 done null
    # J1's first launch, under a name the regex misses: reachable only through sessions[] history
    echo '{"name":"renamed","id":"h0000000","sessionId":"sid-h0000000","state":"stopped","status":null,"pid":null,"waitingFor":null}'
    echo '{"name":"other","id":"z9999999","sessionId":"sid-z","state":"done","status":"idle","pid":14,"waitingFor":null}'
  } | jq -s . > "$CL/agents.json"
  mkdir -p "$R/jobs/J1" "$R/jobs/J2" "$R/jobs/P-J2" "$R/jobs/J10"
  echo '{"job":"J1","state":"done","session_name":"x-J1-r1","short_id":"a2222222","session_id":"sid-a2222222",
    "sessions":[{"name":"x-J1","id":"h0000000","session_id":"sid-h0000000"}]}' > "$R/jobs/J1/status.json"
  echo '{"job":"J2","state":"running"}' > "$R/jobs/J2/status.json"
  echo '{"job":"P-J2","state":"done"}' > "$R/jobs/P-J2/status.json"
  echo '{"job":"J10","state":"done"}' > "$R/jobs/J10/status.json"
}
agents_set() { jq "$1" "$CL/agents.json" > "$CL/a" && mv "$CL/a" "$CL/agents.json"; }
ids_left() { jq -r '[.[].id] | sort | join(" ")' "$CL/agents.json"; }
no_force() { ! grep -qE -- '--discard-unpushed|--force-remove-worktree' "$CL/calls"; }
untouched() { ! grep -qE '^claude (stop|rm)' "$CL/calls"; }

@test "orchestrator-cleanup: done job → stop rows with a pid, rm every name/history match, others untouched" {
  cleanup_setup
  run "$S/orchestrator-cleanup" "$R" J1
  [ "$status" -eq 0 ]
  for id in a1111111 a2222222 b1111111 c1111111 d1111111 h0000000; do [[ $output == *" $id"* ]]; done
  [ "$(grep -c '^claude stop' "$CL/calls")" -eq 2 ]
  grep -qx 'claude stop a1111111' "$CL/calls"
  grep -qx 'claude stop d1111111' "$CL/calls"
  [ "$(ids_left)" = "e1111111 f1111111 g1111111 o0000000 z9999999" ]
  jq -e '.cleaned_at and (.cleaned_sessions | length) == 6' "$R/jobs/J1/status.json"
  no_force
}

@test "orchestrator-cleanup: second run prints absent only and changes nothing" {
  cleanup_setup
  "$S/orchestrator-cleanup" "$R" J1 >/dev/null
  before=$(cat "$R/jobs/J1/status.json"); : > "$CL/calls"
  run "$S/orchestrator-cleanup" "$R" J1
  [ "$status" -eq 0 ]
  [[ $output == *"absent "*" a2222222"* ]]
  [[ $output != *removed* ]]
  untouched
  [ "$(cat "$R/jobs/J1/status.json")" = "$before" ]
}

@test "orchestrator-cleanup: refuses a non-done id (exit 3, nothing touched)" {
  cleanup_setup
  run "$S/orchestrator-cleanup" "$R" J2
  [ "$status" -eq 3 ]
  [[ $output == "refuse J2: state running"* ]]
  untouched
}

# J3 is still running; its planner, plan review and verifier have finished (their status ids are done)
running_job_setup() {
  { cat "$CL/agents.json"; row J3 k0000000 working 30; row P-J3 k1111111 stopped null; row PV-J3 k2222222 done null
    row V-J3 k3333333 done 31; row V-J3-r1 k4444444 done 32; } | jq -s '.[0] + .[1:]' > "$CL/a"
  mv "$CL/a" "$CL/agents.json"
  for j in J3 P-J3 PV-J3 V-J3; do mkdir -p "$R/jobs/$j"; done
  echo '{"job":"J3","state":"running","short_id":"k0000000"}' > "$R/jobs/J3/status.json"
  echo '{"job":"P-J3","state":"done","short_id":"k1111111"}' > "$R/jobs/P-J3/status.json"
  echo '{"job":"PV-J3","state":"done","short_id":"k2222222"}' > "$R/jobs/PV-J3/status.json"
  echo '{"job":"V-J3","state":"done","short_id":"k4444444","sessions":[{"id":"k3333333"},{"id":"k4444444"}]}' \
    > "$R/jobs/V-J3/status.json"
}

@test "orchestrator-cleanup: a done role id is removed while its job still runs; nothing else is touched" {
  cleanup_setup; running_job_setup
  run "$S/orchestrator-cleanup" "$R" V-J3
  [ "$status" -eq 0 ]
  [[ $output == *"removed $slug-V-J3 k3333333"* && $output == *"removed $slug-V-J3-r1 k4444444"* ]]
  grep -qx 'claude stop k3333333' "$CL/calls"
  grep -qx 'claude stop k4444444' "$CL/calls"
  [ "$(grep -c '^claude rm' "$CL/calls")" -eq 2 ]
  jq -e '[.[].id] | index("k0000000") and index("k1111111") and index("k2222222")' "$CL/agents.json"
  jq -e '(.cleaned_sessions | length) == 2' "$R/jobs/V-J3/status.json"
}

@test "orchestrator-cleanup: --all sweep removes finished planners/verifiers of a running job, keeps the job" {
  cleanup_setup; running_job_setup
  run "$S/orchestrator-cleanup" "$R" --all
  [ "$status" -eq 0 ]
  [[ $output == *"skip J3: state running"* ]]
  for id in k1111111 k2222222 k3333333 k4444444; do ! jq -e --arg i "$id" 'any(.id == $i)' "$CL/agents.json"; done
  jq -e 'any(.id == "k0000000")' "$CL/agents.json"
  ! grep -qx 'claude stop k0000000' "$CL/calls"
}

@test "orchestrator-cleanup: --all treats a busy done id as retry-next-tick (exit 0, untouched)" {
  cleanup_setup; running_job_setup
  agents_set 'map(if .id == "k3333333" then .state = "working" else . end)'
  run "$S/orchestrator-cleanup" "$R" --all
  [ "$status" -eq 0 ]
  [[ $output == *"refuse V-J3: session busy or waiting"* ]]
  jq -e 'any(.id == "k3333333") and any(.id == "k4444444")' "$CL/agents.json"
  run "$S/orchestrator-cleanup" "$R" V-J3
  [ "$status" -eq 3 ]
}

@test "orchestrator-launch: relaunching a done role id makes it running, so the sweep keeps the new session" {
  cleanup_setup; running_job_setup
  "$S/orchestrator-cleanup" "$R" V-J3 >/dev/null
  agents_set '. + [{name: "'"$slug"'-V-J3-r2", id: "k5555555", sessionId: "sid-k5555555", state: "idle", status: "idle", pid: 33, waitingFor: null}]'
  jq '.launches = 2' "$R/jobs/V-J3/status.json" > "$R/x" && mv "$R/x" "$R/jobs/V-J3/status.json"
  "$S/orchestrator-launch" "$R" V-J3 "$BATS_TEST_TMPDIR" sonnet medium go
  [ "$(jq -r .state "$R/jobs/V-J3/status.json")" = running ]
  run "$S/orchestrator-cleanup" "$R" --all
  [[ $output == *"skip V-J3: state running"* ]]
  jq -e 'any(.id == "k5555555")' "$CL/agents.json"
}

@test "orchestrator-cleanup: refuses while a session is waiting or busy" {
  cleanup_setup
  agents_set 'map(if .id == "c1111111" then .waitingFor = "permission prompt" | .status = "waiting" else . end)'
  run "$S/orchestrator-cleanup" "$R" J1
  [ "$status" -eq 3 ]
  [[ $output == *"busy or waiting"*"PV-J1"* ]]
  agents_set 'map(if .id == "c1111111" then .waitingFor = null | .status = null | .state = "working" else . end)'
  run "$S/orchestrator-cleanup" "$R" J1
  [ "$status" -eq 3 ]
  untouched
}

@test "orchestrator-cleanup: refuses a merged_sha that is not on the default branch" {
  cleanup_setup
  g="$BATS_TEST_TMPDIR/repo"; git init -q -b main "$g"
  git -C "$g" -c user.email=t@t -c user.name=t commit -q --allow-empty -m a
  git -C "$g" checkout -q -b side
  git -C "$g" -c user.email=t@t -c user.name=t commit -q --allow-empty -m b
  side=$(git -C "$g" rev-parse HEAD); git -C "$g" checkout -q main
  "$S/orchestrator-set-status" "$R" J1 done merged --field merged_sha="$side" --field merged_repo="$g"
  run "$S/orchestrator-cleanup" "$R" J1
  [ "$status" -eq 3 ]
  [[ $output == *"not on main"* ]]
  untouched
  git -C "$g" merge -q --ff-only side
  run "$S/orchestrator-cleanup" "$R" J1
  [ "$status" -eq 0 ]
}

@test "orchestrator-cleanup: rm refusal → kept and stopped, exit 4, never a force flag" {
  cleanup_setup
  echo d1111111 > "$CL/rm-fail"
  run "$S/orchestrator-cleanup" "$R" J1
  [ "$status" -eq 4 ]
  [[ $output == *"kept $slug-V-J1-r2: has unpushed commits"* ]]
  [ "$(jq -r '.[] | select(.id == "d1111111") | .pid' "$CL/agents.json")" = null ]
  no_force
}

@test "orchestrator-cleanup: --all cleans done ids only, never the orchestrator; --dry-run touches nothing" {
  cleanup_setup
  run "$S/orchestrator-cleanup" "$R" --all --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"skip J2: state running"* ]]
  [[ $output == *"would-remove $slug-J10 g1111111"* && $output == *"would-remove $slug-P-J2 f1111111"* ]]
  [[ $output != *o0000000* && $output != *e1111111* ]]
  untouched
  run "$S/orchestrator-cleanup" "$R" --all
  [ "$status" -eq 0 ]
  [ "$(ids_left)" = "e1111111 o0000000 z9999999" ]
  run "$S/orchestrator-cleanup" "$R" orchestrator
  [ "$status" -eq 3 ]
}

@test "orchestrator-launch: every launch is appended to sessions[]" {
  cleanup_setup
  row J5 j0000000 working 20 | jq -s . > "$CL/agents.json"
  "$S/orchestrator-launch" "$R" J5 "$BATS_TEST_TMPDIR" sonnet medium go
  row J5-r1 j1111111 working 21 | jq -s . > "$CL/agents.json"
  "$S/orchestrator-launch" "$R" J5 "$BATS_TEST_TMPDIR" sonnet medium go
  jq -e --arg s "$slug" '.short_id == "j1111111" and ([.sessions[] | .name + "=" + .id + "=" + .session_id]
    == [$s + "-J5=j0000000=sid-j0000000", $s + "-J5-r1=j1111111=sid-j1111111"])' "$R/jobs/J5/status.json"
}

@test "orchestrator-set-status: --field sets extra fields; a malformed --field is a usage error" {
  "$S/orchestrator-set-status" "$R" J1 blocked "merge J1 abc" --field merged_sha=abc
  jq -e '.merged_sha == "abc" and .step == "merge J1 abc" and .state == "blocked"' "$R/jobs/J1/status.json"
  run "$S/orchestrator-set-status" "$R" J1 done x --field nokey
  [ "$status" -eq 2 ]
}
