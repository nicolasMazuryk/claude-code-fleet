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
