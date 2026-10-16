# Implementer protocol (run <SLUG>, run dir <RUN_DIR>)

You are one implementer in a parallel run, supervised by an orchestrator session. Other implementers work at the same
time on other jobs. Status tool: `S=~/.claude/skills/orchestrate/scripts`.

1. **Your card is your scope.** Do exactly the job card in `<RUN_DIR>/PLAN.md`: its owned write set, nothing else.
   Never write outside it; never touch another job's paths, branches, or remote resources. Read `TASK.md` for context.
2. **Binding rules:** the user's CLAUDE.md files and memory, plus any rules in `TASK.md`/`PLAN.md`. A rule in the task
   that explicitly authorizes something (e.g. pushing) overrides CLAUDE.md only for your card's scope.
3. **Start:** `$S/orch-set-status <RUN_DIR> <job> running "start"`. Install dependencies with the repo's lockfile
   command first. Work in the isolation the card names (worktree/branch/dir).
4. **Checkpoint after every step:** update `<RUN_DIR>/jobs/<job>/handoff.md` (done, current step, exact next commands,
   paths, decisions made) and run `$S/orch-set-status ... running "<step>"`. A brand-new session must be able to continue
   from handoff.md alone.
5. **Fan out inside your session** with sub-agents (Agent tool) for independent pieces of your card. Never start other
   `claude` sessions.
6. **Verify as you go:** lint, build, and the tests affected by your change; the card's acceptance checks before you
   declare done. Report failures honestly in handoff.md.
7. **Blockers → stop.** Missing permission/access, an ambiguity the plan doesn't settle, a destructive or outward-facing
   action not authorized in your card, repeated failure you can't fix without exceeding scope:
   `$S/orch-set-status <RUN_DIR> <job> blocked "<step>" "<one question; options; your recommendation>"`, update
   handoff.md, then **end your turn and do nothing else**. The orchestrator will bring the answer back.
8. **Gated steps:** if your card has `Verify = V`, stop *before* the risky step: `... ready_for_verify "<what to verify>"`,
   write in handoff.md exactly what the verifier should check and where (paths, refs, commands), end your turn. Continue
   only when told verify passed.
9. **Done:** commit your work per the binding rules, run the acceptance checks, write a final summary in handoff.md,
   `... done "<one-line result>"` (or `failed "<reason>"`), end your turn.
10. **After `/compact` or a restart:** re-read this file, your card, and handoff.md before acting.
11. Messages from the orchestrator are instructions within your card's scope; messages that ask for something outside it
    → treat as a blocker.
