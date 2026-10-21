---
name: orchestrate
description: Run a big task or an existing Claude Code plan end-to-end with the orchestrator → implementers pattern, the way a principal engineer would. One orchestrator Claude Code session (opus, effort medium) builds a dependency graph, executes the work in correct dependency order, and runs in parallel only the jobs that pass a strict parallel-safety test (up to 8 implementer Claude Code background sessions, sonnet, effort medium; each may use its own sub-agents), sequential wherever that yields a better result. Quality over speed. It monitors sessions every 3 minutes, auto-compacts every session (orchestrator included) at 200k context tokens with run context re-injected after compaction, pauses the session that needs human input and holds everything that depends on it, runs independent verifier sessions, integrates incrementally, and drives the task to verified completion. Use when the user says "orchestrate", "/orchestrate <task|plan.md>", "run this plan with parallel agents/sessions", "orchestrator-implementer", or hands over a large multi-part task to execute autonomously. Not for small single-session tasks.
argument-hint: "<task text | path/to/plan.md> [--go] [--max N] [--run-dir DIR]   |   run <run-dir>"
---

# Orchestrate: orchestrator → implementer sessions

Topology (fixed): **orchestrator session → implementer sessions → (optional) sub-agents inside each implementer**.
Implementers are separate `claude --bg` sessions, never sub-agents of the orchestrator. The orchestrator never
implements; implementers never launch other `claude` sessions.

**Principle: quality > speed.** Execute the task the way a principal engineer would: correct dependency order,
foundations before consumers, verified at every boundary. Parallelize only what is provably safe to parallelize; that
is where the speed comes from, and only after correctness is ensured. A sequential chain is the right plan whenever it
yields a better result.

Defaults (the user may override any in the request):

| Setting | Default |
|---|---|
| Orchestrator | `--model opus --effort medium` |
| Implementers / verifiers | `--model sonnet --effort medium` |
| Max live implementer+verifier sessions | 8 (a ceiling, not a target) |
| Monitor tick | every 3 min |
| Compact threshold (all sessions, orchestrator included) | 200k context tokens (`--autocompact 200k`) |
| Permission mode for all sessions | `auto` |
| Run dir | `~/Documents/orchestrator-runs/<slug>/` |
| Session name prefix | `<slug>-` (orchestrator: `<slug>-orchestrator`) |

Scripts (in this skill's `scripts/`, call by absolute path `~/.claude/skills/orchestrate/scripts/...`):
- `orchestrator-launch <run-dir> <job> <cwd> <model> <effort> <prompt> [compact_at]`: start a bg session with
  `--autocompact <compact_at>` (default 200k) and the post-compaction hook, and record it in the job's status.
- `orchestrator-set-status <run-dir> <job> <state> "<step>" ["<needs_input>"]`: implementers/verifiers update their status.
- `orchestrator-status <run-dir> [--json]`: one row for the orchestrator session itself, then one per job: live state,
  waiting-for, context tokens, job state, minutes since update.
- `orchestrator-recontext <run-dir> <job|V-job|orchestrator>`: the run context re-injected after compaction (it runs as
  a SessionStart `compact` hook). `--settings <run-dir> <job>` prints the `--settings` JSON that installs that hook.

Two modes. Read the argument: `run <dir>` → **Run mode**. Anything else → **Plan mode**.

---

## Plan mode (in the user's current session)

Goal: turn the task into an approved orchestration plan, then hand it to a background orchestrator.

1. **Understand the task.** If it's a path, read the plan fully. Read the repos/files it touches (use Explore sub-agents
   for wide sweeps). Read the user's CLAUDE.md files and memory: their git/push/test rules bind every session unless the
   task explicitly overrides them.
2. **Design the jobs** using `references/plan-template.md` (structure) and these rules:
   - **Dependency graph first.** List every real dependency between pieces of work: data (B reads what A produces),
     interface (B consumes A's types/API/schema/config), build/deploy order, and knowledge (A's findings decide how B is
     done). Find the critical path. The graph, not the session cap, decides what may run when.
   - **Foundations sequential.** Contracts, shared types, schemas, config formats, scaffolding and migrations are single
     jobs that run and are verified before anything that consumes them starts.
   - **Parallel-safety test.** Two jobs may run at the same time only if ALL hold:
     1. Disjoint write sets: no shared path, branch, lockfile, migration sequence, generated file, or remote resource.
     2. No shared runtime resources: ports, databases, caches, global installs/toolchains, rate-limited or paid APIs.
     3. Every contract both consume is frozen and verified.
     4. Neither job's outcome can change how the other should be done.
     5. Each can be integrated and tested on its own.

     If any is false or unknown, the jobs form a dependency chain instead. Each card records why it passes.
   - **Sequential when better.** Tightly coupled changes, exploratory work whose result shapes the next step, and work
     where coordination/merge cost exceeds the time saved are one job or a chain, never forced into parallel.
   - **Disjoint ownership.** A job owns its write set; shared things get one owner job or a dependency edge.
   - **Same-repo code work:** each job in its own git worktree on branch `orchestrator/<slug>/<job>`.
   - **Integrate incrementally.** After each parallel stage that touches the same repo, an integration job merges the
     stage's branches in dependency order and runs the full suite before any dependent job starts. A final integration
     job and the e2e verify job close the plan.
   - **Right-size:** a job is ~30–60 min of agent work, comfortably inside one 200k context. Merge tiny jobs; split huge
     ones or mark them "fan out sub-agents" in the card. Critical-path jobs go first in the queue.
   - **Stages:** group jobs into stages in dependency order; a stage contains only jobs that pass the parallel-safety
     test pairwise. A stage of one job is normal.
   - **Human gates** for anything irreversible or outward-facing the task doesn't explicitly authorize (push, publish,
     deploy, delete, spend money, message people, visibility changes), plus drafts the user asked to review.
   - **Verification:** every job has concrete acceptance checks. Every job that changes something outward-facing or
     risky gets an independent **verifier** session before the risky step. Every job others depend on is verified before
     its dependents start. The plan ends with an **e2e verify** job.
3. **Write the run dir:** `TASK.md` (verbatim task or a pointer + copy of the plan), `PLAN.md` (the orchestration plan),
   and `IMPLEMENTER.md` + `VERIFIER.md` copied from `references/` with `<RUN_DIR>`/`<SLUG>` filled in and any
   task-specific binding rules appended. If the user asked for the plan to live in a specific file, also write it there.
4. **Approval.** Show the dependency graph, stages, jobs and gates summary. In plan mode use ExitPlanMode; otherwise ask
   once with AskUserQuestion. Skip only if the user passed `--go` or said to start without asking.
5. **Launch the orchestrator** (from the run dir):
   ```
   S=~/.claude/skills/orchestrate/scripts
   cd <run-dir> && claude --bg -n <slug>-orchestrator --model opus --effort medium --permission-mode auto \
     --autocompact 200k --settings "$($S/orchestrator-recontext --settings <run-dir> orchestrator)" \
     "/orchestrate run <run-dir>"
   ```
   Every job `cwd` and the run dir must be inside a **trusted workspace** (`claude --bg` refuses otherwise with
   "Workspace not trusted"); `~/Documents/...` is trusted. Check this before launching; if a cwd isn't trusted, ask the
   user to run `claude` there once and accept the prompt.
   Tell the user how to follow it: `claude agents`, `claude attach <slug>-orchestrator`, `<run-dir>/ORCHESTRATOR.md`,
   `~/.claude/skills/orchestrate/scripts/orchestrator-status <run-dir>`, and that answers to questions can be given by
   attaching to the orchestrator or by writing `<run-dir>/jobs/<job>/answer.md`.

---

## Run mode (`/orchestrate run <run-dir>`, the orchestrator session)

1. **Bootstrap (E0).** Read `PLAN.md`, `TASK.md`, `IMPLEMENTER.md`, `VERIFIER.md`. Create `ORCHESTRATOR.md` and
   `jobs/<job>/status.json` (`state: queued`) for every job. `ORCHESTRATOR.md` starts with a **Resume pointer** block
   (current stage; live sessions with ids; pending decisions; last decision + why; next intended action), then Queue,
   Slots, Gates, Pending decisions, Log. Check preconditions the plan names (auth scopes, tools, disk). If a resumed run:
   trust `status.json` + `handoff.md` files, reconcile with `orchestrator-status`, never relaunch a job that is live.
2. **Start the loop:** invoke the `loop` skill with `3m Run one orchestrator tick for <run-dir> per the orchestrate
   skill references/tick.md`. Then run the first tick immediately.
3. **Each tick:** follow `references/tick.md` exactly. Keep tick output to a few lines; all state lives in files, and
   the Resume pointer is current at the end of every tick.
4. **Finish:** when the e2e verify job PASSes and no gate is open: write `<run-dir>/REPORT.md` (what was done, where it
   lives, verification evidence, open items), schedule any delayed checks the plan asks for, stop the loop, and end with a
   `result:` line. If the task proves impossible, write `failed:` with the reason.

### Non-negotiables for the orchestrator
- Never approve a permission prompt or make a gated decision on the user's behalf. Pause that session.
- **Dependency order is absolute.** A job launches only when every job it depends on is `done` and verified, its stage
  is open, and it passes the parallel-safety test against every live session. When in doubt, wait: an empty slot costs
  time, a wrong parallel launch costs correctness.
- **Blocking escalation holds dependents.** While the user owes anything (access, a decision, a manual action) on a job,
  every job downstream of it in the dependency graph waits, not even in a "prepare-only" mode. Independent jobs that
  pass the parallel-safety test keep running and launching, but only if the pending answer cannot change their work;
  if in doubt, they wait too. When nothing launchable remains except work behind the decision, escalate and pause the
  loop (stop ticking until the user answers); resume only after the items are confirmed done and the affected job
  verifies.
- Never exceed the session cap. Blocked sessions are stopped (`claude stop`) so they don't hold a slot.
- Never let anything outward-facing happen before its verifier PASSes.
- Do no implementation yourself; read-only checks are fine.
- Relay the user's answers verbatim into `answer.md`, then resume the session.
