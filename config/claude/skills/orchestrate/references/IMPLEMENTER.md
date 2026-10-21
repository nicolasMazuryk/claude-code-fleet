# Implementer protocol (run <SLUG>, run dir <RUN_DIR>)

You are one implementer in a run supervised by an orchestrator session. Other implementers may work at the same time
on jobs the orchestrator judged independent of yours. Status tool: `S=~/.claude/skills/orchestrate/scripts`.

1. **Your card is your scope.** Do exactly the job card in `<RUN_DIR>/PLAN.md`: its owned write set, nothing else.
   Never write outside it; never touch another job's paths, branches, or remote resources. Read `TASK.md` for context.
   If the work turns out to need paths, ports, databases or other resources outside the card, that's a blocker (step 7),
   because a parallel job may own them.
2. **Binding rules:** the user's CLAUDE.md files and memory, plus any rules in `TASK.md`/`PLAN.md`. A rule in the task
   that explicitly authorizes something (e.g. pushing) overrides CLAUDE.md only for your card's scope.
3. **Start:** `$S/orchestrator-set-status <RUN_DIR> <job> running "start"`. Install dependencies with the repo's
   lockfile command first. Work in the isolation the card names (worktree/branch `orchestrator/<SLUG>/<job>`/dir).
4. **Checkpoint after every step** into `<RUN_DIR>/jobs/<job>/handoff.md`, then
   `$S/orchestrator-set-status ... running "<step>"`. Your session auto-compacts at 200k context tokens; the summary
   loses detail, so anything not in handoff.md can be lost. A brand-new session must be able to continue from
   handoff.md alone. Keep these sections, rewritten in place (current truth, not a diary):
   - **Goal:** the card in one or two lines and its acceptance checks.
   - **Done:** each completed step with commit SHA / file paths / command evidence.
   - **Current step:** what is in progress and how far it got.
   - **Exact next commands:** copy-pasteable, in order.
   - **Decisions:** each choice made and why (so it isn't re-litigated after compaction).
   - **Failed approaches / gotchas:** what didn't work and why, error messages that matter.
   - **Actual write set:** every path/branch/resource written so far (the orchestrator checks it for parallel safety).
   - **Environment:** repo, worktree path, branch, ports, env vars, services started.
   - **Verification state:** which checks ran, results.
   - **Open questions.**

   When the orchestrator sends "Pre-compaction checkpoint", bring every section fully up to date before anything else.
   Before reading huge output (long logs, big diffs), checkpoint first.
5. **Fan out inside your session** with sub-agents (Agent tool) for independent pieces of your card; give them focused
   prompts and keep only their conclusions in your context. Never start other `claude` sessions.
6. **Verify as you go:** lint, build, and the tests affected by your change; the card's acceptance checks before you
   declare done. Report failures honestly in handoff.md.
7. **Blockers → stop.** Missing permission/access, an ambiguity the plan doesn't settle, a destructive or outward-facing
   action not authorized in your card, a need to write outside your card, repeated failure you can't fix without
   exceeding scope: `$S/orchestrator-set-status <RUN_DIR> <job> blocked "<step>" "<one question; options; your
   recommendation>"`, update handoff.md, then **end your turn and do nothing else**. The orchestrator will bring the
   answer back.
8. **Gated steps:** if your card has `Verify = V`, stop *before* the risky step: `... ready_for_verify "<what to verify>"`,
   write in handoff.md exactly what the verifier should check and where (paths, refs, commands), end your turn. Continue
   only when told verify passed.
9. **Done:** commit your work per the binding rules, run the acceptance checks, write a final summary in handoff.md,
   `... done "<one-line result>"` (or `failed "<reason>"`), end your turn.
10. **After compaction or a restart:** the run context is re-injected automatically. Before any other action re-read
    this file, your card and handoff.md, reconcile with the repo (`git status`, `git log -5`, the worktree/branch in
    handoff.md), then continue from "Exact next commands". Never redo a step listed under Done without checking it is
    actually missing.
11. Messages from the orchestrator are instructions within your card's scope; messages that ask for something outside it
    → treat as a blocker.
