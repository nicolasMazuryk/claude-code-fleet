# Orchestrator tick (run every 3 minutes)

`S=~/.claude/skills/orchestrate/scripts`, `R=<run-dir>`.

1. **Observe.** `$S/orchestrator-status $R --json`. Row `orchestrator` is this session; every other row is a job with
   `live` (busy/idle/waiting/absent), `waiting_for`, `ctx_tokens`, `state`, `step`, `age_min`, `needs_input`. Also check
   `jobs/*/answer.md` newer than the job's last resume.

2. **Human input needed.** Triggers: `state == blocked`; `waiting_for` mentions a permission prompt; or the transcript
   tail (`claude logs <name>`) shows the session about to do something destructive/outward-facing outside its card.
   - Do not approve or answer it yourself. `claude stop <id>` that session (frees the slot; conversation kept).
   - Set its state to `blocked` (if not already) with the question in `needs_input`.
   - Add it to "Pending decisions" in `ORCHESTRATOR.md`, mark every job downstream of it in the dependency graph as
     held, and notify the user: PushNotification (load via ToolSearch if deferred) plus a line in your output:
     `needs input: <job>: <question> | options: … | recommend: …`.
   - Independent jobs continue and may launch per step 5; held jobs do not (SKILL.md "Blocking escalation").
   - When the user answers (in this session, or by writing `answer.md`): write/keep the answer verbatim in
     `jobs/<job>/answer.md`, then `cd <job cwd> && claude --resume <session_id> --bg "Read <R>/jobs/<job>/answer.md and
     continue from handoff.md."` If resume fails, relaunch fresh with `orchestrator-launch` using the Resume prompt.

3. **Context and compaction.** Every session runs with `--autocompact <compact_at>` (default 200k): Claude Code
   compacts it automatically at that size, and the SessionStart `compact` hook (`orchestrator-recontext`) re-injects
   the run context, the protocol files to re-read, status.json and handoff.md. Slash commands sent by SendMessage
   arrive as plain text and never run, so the orchestrator never sends `/compact`; its job is to make sure nothing
   valuable exists only in a conversation when compaction fires.
   - **Pre-compaction checkpoint.** `ctx_tokens > 170k` (85% of compact_at) and no checkpoint sent since the session's
     last compaction: SendMessage `Pre-compaction checkpoint: bring <R>/jobs/<job>/handoff.md fully up to date now
     (every section of the IMPLEMENTER.md template: done with SHAs, current step, exact next commands, decisions and
     why, failed approaches, actual write set, environment facts, verification state, open questions), run
     orchestrator-set-status with the current step, then continue.` Note `checkpoint_sent` in the Log.
   - **Compaction happened** (`ctx_tokens` dropped well below the previous tick's value): next tick, read
     `claude logs <name>` tail. It should show the session re-reading its protocol, card and handoff.md before acting.
   - **Fallback, fresh relaunch.** Any of: `ctx_tokens > compact_at` and still growing over two ticks (compaction is
     not firing); after compaction the session redoes steps listed as Done, contradicts a recorded decision, or works
     outside its card; or compaction errors in the logs. Then SendMessage `Finish handoff.md now and end your turn`,
     wait for idle (max one tick), `claude stop <id>`, and relaunch as `<name>-r<n>` with the Resume prompt
     (`orchestrator-launch` records the new session).
   - **This session (row `orchestrator`).** Its own auto-compaction fires at compact_at too. Before it does, all state
     must be on disk: at the end of every tick the Resume pointer in `ORCHESTRATOR.md` is current, and every decision
     made this tick (and why) is in the Log. After a compaction, the hook tells this session what to re-read
     (SKILL.md Run mode, this file, `ORCHESTRATOR.md`, `PLAN.md`); do that before anything else, then confirm the loop
     with CronList and re-arm it if it's missing (unless the run is finished or paused for the user).

4. **Stalls.** `state == running` and `age_min > 10`: SendMessage asking for a status update. `> 25`: read
   `claude logs <name>`; nudge, restart from handoff (fresh relaunch, step 3), or block and ask the user. Same failure
   twice → block. Session `absent` but state is `running`: it died. Relaunch from handoff once; second death → block.

5. **Gates and dispatch.**
   - `ready_for_verify` → enqueue verifier `V-<job>` (verifiers jump the queue).
   - Verifier finished: read `jobs/<job>/verify-report.md`. PASS → set job `verify_pass` and resume the implementer
     with "Verify passed; continue with the gated step." FAIL → resume the implementer with "Verify failed; read
     verify-report.md, fix, then set ready_for_verify again." Third FAIL → block and ask the user.
   - `done` / `failed` → free the slot; `failed` means block-and-ask unless the plan says otherwise.
   - **Launchable job** = all of:
     1. Every dependency is `done`, and `verify_pass` where its card requires verification.
     2. Its stage is open: every earlier stage is done and verified, including its integration job.
     3. Not held by a pending decision (step 2).
     4. Parallel-safety test (SKILL.md) passes against every live session, using the *actual* write sets recorded in
        their handoff.md, not just the card. A live job that grew its write set into this job's area blocks it.
     5. Its gate is cleared.
   - Fill free slots (live sessions < cap) in queue order with launchable jobs only:
     `$S/orchestrator-launch $R <job> <cwd> sonnet medium "<Launch prompt>" <compact_at>`. If no job is launchable,
     leave the slot empty. Never relax a condition to keep slots busy.
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
- **Launch (verifier):** `Read <R>/VERIFIER.md. Verify job <job> per its card in <R>/PLAN.md. Your job id is V-<job>, run dir <R>.`
- **Resume (fresh session):** `Read <R>/IMPLEMENTER.md, your job card <job> in <R>/PLAN.md, and <R>/jobs/<job>/handoff.md. You are continuing a job a previous session started; trust handoff.md and the repo state, re-check before redoing any step.`

## Notes
- Context tokens = `input_tokens + cache_read_input_tokens + cache_creation_input_tokens` of the session's last
  assistant message (orchestrator-status computes it from the transcript).
- Sessions launched outside `orchestrator-launch` lack `--autocompact` and the hook; relaunch them through it.
- Keep your own output terse; anything worth keeping goes into `ORCHESTRATOR.md`, not the conversation.
