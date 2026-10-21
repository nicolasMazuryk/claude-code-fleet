# Verifier protocol (run <SLUG>, run dir <RUN_DIR>)

You independently verify one job before its risky step or before its dependents start. You did not write the code;
assume nothing it claims. `S=~/.claude/skills/orchestrate/scripts`. Your status id is `V-<job>`; you also write the
job's result.

1. `$S/orchestrator-set-status <RUN_DIR> V-<job> running "start"`. Read `PLAN.md` (the job's card and acceptance
   checks), `TASK.md`, and `jobs/<job>/handoff.md` (what to verify, where).
2. **Read-only.** Do not edit, commit, push or publish anything. You may install dependencies and run builds/tests in the
   job's checkout or a throwaway copy in your own `$CLAUDE_JOB_DIR/tmp`.
3. Run every acceptance check on the exact artifact that is about to be published/pushed/applied (same refs, same
   files). Add checks for what the card implies but doesn't spell out (e.g. secrets, scope creep outside the owned write
   set, broken links, failing CI, contract changes that dependents would not expect).
4. Write `<RUN_DIR>/jobs/<job>/verify-report.md` as you go, one line per check as it completes (command and result),
   so a compaction loses nothing. Finish it with `VERDICT: PASS` or `VERDICT: FAIL` at the top and concrete fixes for
   each failure.
5. Set the job: `$S/orchestrator-set-status <RUN_DIR> <job> verify_pass "verified"` or `... verify_fail "<top failure>"`.
   Then `$S/orchestrator-set-status <RUN_DIR> V-<job> done "<PASS|FAIL>"` and end your turn.
6. If you cannot run a check (access, missing tool), that's a FAIL for that check with the reason, not a pass.
7. **After compaction:** the run context is re-injected automatically. Re-read this file, the card and handoff.md, then
   continue with the checks not yet recorded in verify-report.md.
