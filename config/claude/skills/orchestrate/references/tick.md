# Orchestrator tick (run every 3 minutes)

`S=~/.claude/skills/orchestrate/scripts`, `R=<run-dir>`.

1. **Observe.** `$S/orchestrator-status $R --json`. Row `orchestrator` is this session; every other row is a job with
   `role`, `live` (busy/idle/waiting/absent), `waiting_for`, `ctx_tokens`, `state`, `step`, `age_min`, `needs_input`,
   and for live planners `plan` (ready/asking/none). Also check `jobs/*/answer.md` newer than the job's last resume.

2. **Human input needed.** Triggers: `state == blocked` (except a merge request, below); `waiting_for` mentions a permission prompt (except a planner
   with `plan: ready`, which waits on ExitPlanMode and is handled in step 5); or the transcript
   tail (`claude logs <name>`) shows the session about to do something destructive/outward-facing outside its card.
   - Do not approve or answer it yourself. `claude stop <id>` that session (frees the slot; conversation kept).
   - Set its state to `blocked` (if not already) with the question in `needs_input`.
   - Add it to "Pending decisions" in `ORCHESTRATOR.md`, mark every job downstream of it in the dependency graph as
     held, and notify the user with a line in your output (Agent View turns it into a presence-gated ntfy push; never use PushNotification):
     `needs input: <job>: <question> | options: … | recommend: …`.
   - Independent jobs continue and may launch per step 5; held jobs do not (SKILL.md "Blocking escalation").
   - When the user answers (in this session, or by writing `answer.md`): write/keep the answer verbatim in
     `jobs/<job>/answer.md`, then `cd <job cwd> && claude --resume <session_id> --bg "Read <R>/jobs/<job>/answer.md and
     continue from handoff.md."` If resume fails, relaunch fresh with `orchestrator-launch` using the Resume prompt.
   - **Merge requests** (`state == blocked`, step `merge <job> <sha>`) are not a human decision. Check that `<sha>` is
     the tip of `orchestrator/<slug>/<job>`, that the job's verifier PASSed on it (when the card has Verify = V), and
     that the default branch's checkout is clean. Then `git -C <repo> merge --ff-only <sha>` in that checkout, Log it,
     and resume the session with `Merged <sha> into <branch>; continue from handoff.md.` A dirty checkout or a
     non-fast-forward is a normal block (above).

3. **Context: planned handoff and compaction.** Workers (planner/implementer/verifier) launch with
   `--autocompact <compact_at>` (workers' value in PLAN.md `## Settings`, default 300k), which is only a safety net. The
   orchestrator launches with 200k. `handoff_at` (180k) comes from `## Settings`. Every session has the SessionStart
   `compact` hook (`orchestrator-recontext`), which re-injects the run context after a compaction. Slash commands sent
   by SendMessage arrive as plain text and never run, so the orchestrator never sends `/compact`.
   - **Planned handoff.** Trigger: a worker's `ctx_tokens > handoff_at` and no `handoff_sent` Logged for this session
     yet. Send by role:
     - implementer/verifier: SendMessage `Planned handoff: finish your current step (don't start a new one), bring
       handoff.md (verifier: verify-report.md / plan-review.md) fully up to date per your protocol, run
       orchestrator-set-status with the current step, then end your turn. A fresh session will continue.`
     - planner: SendMessage `Planned handoff: stop exploring and call ExitPlanMode now with the plan so far, plus a
       "## Remaining exploration" section listing what is still unexplored and what you found so far.`
     - Log `handoff_sent <job>` (with the session name).
   - **After the handoff is sent:** wait until the session is idle (a planner: `plan: ready`), at most 2 ticks; past
     that, stop it anyway and Log `handoff_timeout <job>`. Then:
     - implementer/verifier: `claude stop <id>`, then relaunch with `orchestrator-launch` for the same status id
       (`<job>`, `V-<job>`, `PV-<job>`; `-r<n>` naming is automatic) and the role's continue prompt: Resume (fresh
       session), Continue (verifier).
     - planner: `$S/orchestrator-plan $R <job>`, then `mv $R/jobs/<job>/plan.md $R/jobs/<job>/plan-draft.md` (a draft
       is never plan.md and never sets `plan_ready`), `claude stop <id>`, and relaunch `P-<job>` with `--plan` and
       Continue (planner). If it never reached `ready` (timeout), relaunch with Continue (planner) when an
       earlier `plan-draft.md` exists, otherwise with Launch (planner).
     - The slot carries over: a handoff relaunch does not count as a new launch against the cap. Log `handoff_relaunch
       <job> <new name>`.
   - **Fallback, unplanned.** Any of: `ctx_tokens > compact_at` and still growing over two ticks (compaction is not
     firing); after a compaction the session redoes steps listed as Done, contradicts a recorded decision, or works
     outside its card; compaction errors in the logs; a planned handoff that hasn't reached idle after 2 ticks. Then
     `claude stop <id>` and relaunch through the planned-handoff path above (Log the reason).
   - **Compaction happened** (`ctx_tokens` dropped well below the previous tick's value without a handoff relaunch;
     the 300k safety net fired): next tick, read `claude logs <name>` tail. It should show the session re-reading its
     protocol, card and handoff.md before acting; otherwise take the fallback.
   - **This session (row `orchestrator`).** Its own auto-compaction fires at 200k. Before it does, all state must be on
     disk: at the end of every tick the Resume pointer in `ORCHESTRATOR.md` is current, and every decision made this
     tick (and why) is in the Log. After a compaction, the hook tells this session what to re-read (SKILL.md Run mode,
     this file, `ORCHESTRATOR.md`, `PLAN.md`); do that before anything else, then confirm the loop with CronList and
     re-arm it if it's missing (unless the run is finished or paused for the user).

4. **Stalls.** `state == running` and `age_min > 10`: SendMessage asking for a status update. `> 25`: read
   `claude logs <name>`; nudge, restart from handoff (planned handoff path, step 3), or block and ask the user. Same failure
   twice → block. Session `absent` but state is `running`: it died. Relaunch from handoff once; second death → block.

5. **Gates and dispatch.** Every launch takes its role's model/effort from PLAN.md `## Settings` (orchestrator,
   planner, implementer, verifier), never a hard-coded value.
   - `ready_for_verify` → enqueue verifier `V-<job>` (verifiers jump the queue).
   - Verifier finished: read `jobs/<job>/verify-report.md`. PASS → set job `verify_pass` and resume the implementer
     with "Verify passed; continue with the gated step." FAIL → resume the implementer with "Verify failed; read
     verify-report.md, fix, then set ready_for_verify again." Third FAIL → block and ask the user.
   - `done` / `failed` → free the slot; `failed` means block-and-ask unless the plan says otherwise.
   - **Plan-first jobs** (`Plan first` = `yes` or `yes+review`) go queued → `planning` → `plan_ready` →
     `plan_approved` → implementer. A `yes*` implementer launches only from an approved `jobs/<job>/plan.md`.
     1. **Launch planner** when launchable conditions 1–3 and 5 hold (condition 4 is skipped: the planner is
        read-only). It counts toward the session cap. `$S/orchestrator-launch --plan $R P-<job> <cwd> <planner model>
        <planner effort> "<Launch (planner)>" <compact_at>`, then set the job `planning`.
     2. **Each live planner, every tick:** read its `plan` field in orchestrator-status.
        - `ready` with a `handoff_sent` Logged for this planner session: take the plan-draft path in step 3 instead.
        - `ready`: run `$S/orchestrator-plan $R <job>` (writes `jobs/<job>/plan.md`), then `claude stop <id>`.
          Stopping rejects the plan; the orchestrator never approves ExitPlanMode. Set `P-<job> done "plan written"`
          and the job `plan_ready`.
        - `asking`: the planner asked despite the prompt. Handle it as a blocked job (step 2) with the question
          `orchestrator-plan` printed. After the answer is in `jobs/<job>/answer.md`, resume it in plan mode:
          `cd <cwd> && claude --resume <session_id> --bg --permission-mode plan "Read <R>/jobs/<job>/answer.md, finish
          the plan and call ExitPlanMode."`
        - A permission prompt other than ExitPlanMode is a normal step 2 block.
     3. **Plan check** (this session, read-only) on `plan_ready`. Check: every section in PLAN.md § Job plan sections
        is present; the plan's write set is a subset of the card's owned writes; no step takes a gated action the card
        does not authorize; every acceptance check is covered. Write `jobs/<job>/plan-check.md` (`PASS`/`FAIL` on the
        first line, one line per check). FAIL → relaunch the planner once (`P-<job>` gets `-r<n>`) with the
        Revise prompt; a second FAIL blocks the job and asks the user.
     4. **Plan review.** `yes+review`: after the check passes, enqueue verifier `PV-<job>` (jumps the queue, verifier
        model/effort, Launch (plan review) prompt). Read `jobs/<job>/plan-review.md`: PASS → job `plan_approved`;
        FAIL → relaunch the planner with the Revise prompt, then check and review again; a second FAIL blocks the job.
        `yes`: a passed check sets `plan_approved` directly.
   - **Launchable job** = all of:
     1. Every dependency is `done`, and `verify_pass` where its card requires verification.
     2. Its stage is open: every earlier stage is done and verified, including its integration job.
     3. Not held by a pending decision (step 2).
     4. Parallel-safety test (SKILL.md) passes against every live session. For a plan-first candidate the write set is
        the **Write set** in its plan.md; otherwise its card. For each live job use the union of its plan write set
        (if any) and the *actual* write set in its handoff.md. A live job that grew its write set into this job's area
        blocks it. A conflict with a live session means wait; it is not a plan defect.
     5. Its gate is cleared, and for a plan-first job its state is `plan_approved`.
   - Fill free slots (live sessions < cap) in queue order with launchable jobs only:
     `$S/orchestrator-launch $R <job> <cwd> <implementer model> <implementer effort> "<Launch prompt>" <compact_at>`
     with Launch (implementer from plan) for plan-first jobs and Launch (implementer) otherwise. Verifiers use the
     verifier model/effort. If no job is launchable, leave the slot empty. Never relax a condition to keep slots busy.
   - If nothing is live, nothing is launchable, and decisions are pending: notify the user and pause the loop instead
     of ticking on.
   - `orchestrator-launch` fails with "Workspace not trusted" → block that job and ask the user to run `claude` once in
     that cwd and accept the trust prompt (only they can). Other launch failures: retry once next tick, then block.
   - Human-gate jobs (drafts for review): when the job reaches its gate, notify the user as in step 2.

6. **Record.** Append one line per state change or decision (with its reason) to the Log in `ORCHESTRATOR.md`; update
   Slots/Queue/Gates/Pending decisions; rewrite the Resume pointer (current stage; live sessions with ids; pending
   decisions; last decision + why; next intended action). At each stage boundary post a short status report
   (done / running / blocked / next).

7. **Completion check.** All jobs `done`, e2e verify PASS, no pending decisions → Finish (SKILL.md Run mode step 4).

## Prompts
- **Launch (implementer):** `Read <R>/IMPLEMENTER.md, then your job card <job> in <R>/PLAN.md. Your job id is <job>, run dir <R>.`
- **Launch (planner):** `Background run, nobody will answer: do not call AskUserQuestion; record unknowns under Open questions. Read <R>/TASK.md and your card <job> in <R>/PLAN.md. Explore read-only, then write the plan with the required sections in <R>/PLAN.md § Job plan sections and call ExitPlanMode. Your job id is P-<job>, run dir <R>.`
- **Revise (planner relaunch):** the Launch (planner) prompt plus `A previous plan was rejected: revise per <R>/jobs/<job>/plan-check.md (and plan-review.md if present); the previous plan is <R>/jobs/<job>/plan.md.`
- **Launch (plan review):** `Read <R>/VERIFIER.md, section Plan review. Review the plan <R>/jobs/<job>/plan.md for job <job> per its card in <R>/PLAN.md. Your job id is PV-<job>, run dir <R>.`
- **Launch (implementer from plan):** `Read <R>/IMPLEMENTER.md, your card <job> in <R>/PLAN.md and your approved plan <R>/jobs/<job>/plan.md. Implement the plan. Your job id is <job>, run dir <R>.`
- **Launch (verifier):** `Read <R>/VERIFIER.md. Verify job <job> per its card in <R>/PLAN.md. Your job id is V-<job>, run dir <R>.`
- **Resume (fresh session):** `Read <R>/IMPLEMENTER.md, your job card <job> in <R>/PLAN.md, the plan <R>/jobs/<job>/plan.md (when it exists), and <R>/jobs/<job>/handoff.md. You are continuing a job a previous session started; trust handoff.md and the repo state, re-check before redoing any step.`
- **Continue (verifier):** the Launch (verifier) or Launch (plan review) prompt plus `A previous session started this review; continue with the checks not yet recorded in <verify-report.md|plan-review.md>.`
- **Continue (planner):** the Launch (planner) prompt plus `A previous planner ran out of context; its draft is <R>/jobs/<job>/plan-draft.md. Keep its findings, explore only what is under Remaining exploration, and drop that section from the final plan.`

## Notes
- Context tokens = `input_tokens + cache_read_input_tokens + cache_creation_input_tokens` of the session's last
  assistant message (orchestrator-status computes it from the transcript).
- Sessions launched outside `orchestrator-launch` lack the 300k safety net and the hook; relaunch them through it.
- Keep your own output terse; anything worth keeping goes into `ORCHESTRATOR.md`, not the conversation.
