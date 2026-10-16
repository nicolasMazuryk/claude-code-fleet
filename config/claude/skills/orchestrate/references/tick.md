# Orchestrator tick (run every 3 minutes)

`S=~/.claude/skills/orchestrate/scripts`, `R=<run-dir>`.

1. **Observe.** `$S/orch-status $R --json`. Per job: `live` (busy/idle/waiting/absent), `waiting_for`, `ctx_tokens`,
   `state`, `step`, `age_min`, `needs_input`. Also check `jobs/*/answer.md` newer than the job's last resume.

2. **Human input needed.** Triggers: `state == blocked`; `waiting_for` mentions a permission prompt; or the transcript
   tail (`claude logs <name>`) shows the session about to do something destructive/outward-facing outside its card.
   - Do not approve or answer it yourself. `claude stop <id>` that session (frees the slot; conversation kept).
   - Set its state to `blocked` (if not already) with the question in `needs_input`.
   - Add it to "Pending decisions" in `ORCHESTRATOR.md` and notify the user: PushNotification (load via ToolSearch if
     deferred) plus a line in your output: `needs input: <job>: <question> | options: … | recommend: …`.
   - All other jobs continue.
   - When the user answers (in this session, or by writing `answer.md`): write/keep the answer verbatim in
     `jobs/<job>/answer.md`, then `cd <job cwd> && claude --resume <session_id> --bg "Read <R>/jobs/<job>/answer.md and
     continue from handoff.md."` If resume fails, relaunch fresh with `orch-launch` using the Resume prompt below.

3. **Context > 250k tokens.** Only at a safe point (session idle, or `status.json` updated in the last 3 min):
   - A: SendMessage to the session name: `/compact Keep: job card <job>, handoff.md state, current step, next commands.`
     then, once idle, `Continue from handoff.md.`
   - Next tick, if still > 250k: B: `claude stop <id>`, then `claude --resume <session_id> --bg "/compact Keep: job card
     <job>, handoff.md, current step"`, then resume with "Continue from handoff.md."
   - Still > 250k or compaction failed: C: send "Finish handoff.md now and end your turn", stop it, and relaunch as
     `<name>-r<n>` with the Resume prompt. Record the new session in status.json (orch-launch does this).

4. **Stalls.** `state == running` and `age_min > 20`: SendMessage asking for a status update. `> 45`: read
   `claude logs <name>`; nudge, restart from handoff (option C), or block and ask the user. Same failure twice → block.
   Session `absent` but state is `running`: it died. Relaunch from handoff once; second death → block.

5. **Gates and dispatch.**
   - `ready_for_verify` → enqueue verifier `V-<job>` (verifiers jump the queue).
   - Verifier finished: read `jobs/<job>/verify-report.md`. PASS → set job `verify_pass` and resume the implementer
     with "Verify passed; continue with the gated step." FAIL → resume the implementer with "Verify failed; read
     verify-report.md, fix, then set ready_for_verify again." Third FAIL → block and ask the user.
   - `done` / `failed` → free the slot; `failed` means block-and-ask unless the plan says otherwise.
   - Fill free slots (live sessions < cap) in queue order with jobs whose dependencies are `done` and whose gate is
     cleared: `$S/orch-launch $R <job> <cwd> sonnet medium "<Launch prompt>"`.
   - `orch-launch` fails with "Workspace not trusted" → block that job and ask the user to run `claude` once in that cwd
     and accept the trust prompt (only they can). Other launch failures: retry once next tick, then block.
   - Human-gate jobs (drafts for review): when the job reaches its gate, notify the user as in step 2.

6. **Record.** Append one line per state change to the Log in `ORCHESTRATOR.md`; update Slots/Queue/Gates. At each
   phase boundary post a short status report (done / running / blocked / next).

7. **Completion check.** All jobs `done`, e2e verify PASS, no pending decisions → Finish (SKILL.md Run mode step 4).

## Prompts
- **Launch (implementer):** `Read <R>/IMPLEMENTER.md, then your job card <job> in <R>/PLAN.md. Your job id is <job>, run dir <R>.`
- **Launch (verifier):** `Read <R>/VERIFIER.md. Verify job <job> per its card in <R>/PLAN.md. Your job id is V-<job>, run dir <R>.`
- **Resume (fresh session):** `Read <R>/IMPLEMENTER.md, your job card <job> in <R>/PLAN.md, and <R>/jobs/<job>/handoff.md. You are continuing a job a previous session started; trust handoff.md and the repo state, re-check before redoing any step.`

## Notes
- Context tokens = `input_tokens + cache_read_input_tokens + cache_creation_input_tokens` of the session's last
  assistant message (orch-status computes it from the transcript).
- Keep your own output terse; your own context is handled by auto-compaction because all state is in files.
