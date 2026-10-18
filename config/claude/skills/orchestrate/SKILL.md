---
name: orchestrate
description: Run a big task or an existing Claude Code plan end-to-end with the orchestrator → parallel implementers pattern. One orchestrator Claude Code session (opus, effort medium) phases the work, launches up to 8 parallel implementer Claude Code background sessions (sonnet, effort medium; each may use its own sub-agents), monitors them every 3 minutes, compacts any session above 250k context tokens, pauses the session that needs human input and holds every later phase until it is resolved, runs independent verifier sessions, and drives the task to verified completion. Use when the user says "orchestrate", "/orchestrate <task|plan.md>", "run this plan with parallel agents/sessions", "orchestrator-implementer", or hands over a large multi-part task to execute autonomously. Not for small single-session tasks.
argument-hint: "<task text | path/to/plan.md> [--go] [--max N] [--run-dir DIR]   |   run <run-dir>"
---

# Orchestrate: orchestrator → parallel implementer sessions

Topology (fixed): **orchestrator session → implementer sessions → (optional) sub-agents inside each implementer**.
Implementers are separate `claude --bg` sessions, never sub-agents of the orchestrator. The orchestrator never
implements; implementers never launch other `claude` sessions.

Defaults (the user may override any in the request):

| Setting | Default |
|---|---|
| Orchestrator | `--model opus --effort medium` |
| Implementers / verifiers | `--model sonnet --effort medium` |
| Max live implementer+verifier sessions | 8 |
| Monitor tick | every 3 min |
| Compact threshold | 250,000 context tokens |
| Permission mode for all sessions | `auto` |
| Run dir | `~/Documents/orchestrator-runs/<slug>/` |
| Session name prefix | `<slug>-` (orchestrator: `<slug>-orch`) |

Scripts (in this skill's `scripts/`, call by absolute path `~/.claude/skills/orchestrate/scripts/...`):
- `orch-launch <run-dir> <job> <cwd> <model> <effort> <prompt>`: start a bg session and record it in the job's status.
- `orch-set-status <run-dir> <job> <state> "<step>" ["<needs_input>"]`: implementers/verifiers update their status.
- `orch-status <run-dir> [--json]`: one row per job: live state, waiting-for, context tokens, job state, minutes since update.

Two modes. Read the argument: `run <dir>` → **Run mode**. Anything else → **Plan mode**.

---

## Plan mode (in the user's current session)

Goal: turn the task into an approved orchestration plan, then hand it to a background orchestrator.

1. **Understand the task.** If it's a path, read the plan fully. Read the repos/files it touches (use Explore sub-agents
   for wide sweeps). Read the user's CLAUDE.md files and memory: their git/push/test rules bind every session unless the
   task explicitly overrides them.
2. **Design the jobs** using `references/plan-template.md` (structure) and these rules:
   - **Disjoint write sets.** A job owns a set of repos/dirs/branches/remote resources. No two concurrent jobs write the
     same path, branch, lockfile, schema, or remote resource. Shared things get one owner job or a dependency edge.
   - **Same-repo code work:** each job in its own git worktree on branch `orch/<slug>/<job>`; add a final
     **integration job** that merges branches in dependency order and runs the full suite.
   - **Contracts first:** if jobs share an interface (types, API, schema, config format), a first job defines it.
   - **Right-size:** a job is ~30–180 min of agent work. Merge tiny jobs; split huge ones or mark them "fan out
     sub-agents" in the card. Long/critical-path jobs go first in the queue.
   - **Human gates** for anything irreversible or outward-facing the task doesn't explicitly authorize (push, publish,
     deploy, delete, spend money, message people, visibility changes), plus drafts the user asked to review.
   - **Verification:** every job has concrete acceptance checks. Every job that changes something outward-facing or
     risky gets an independent **verifier** session before the risky step. The plan ends with an **e2e verify** job.
   - **Waves:** respect the session cap; the queue refills slots as jobs finish (verifiers first).
3. **Write the run dir:** `TASK.md` (verbatim task or a pointer + copy of the plan), `PLAN.md` (the orchestration plan),
   and `IMPLEMENTER.md` + `VERIFIER.md` copied from `references/` with `<RUN_DIR>`/`<SLUG>` filled in and any
   task-specific binding rules appended. If the user asked for the plan to live in a specific file, also write it there.
4. **Approval.** Show the phases/jobs/gates summary. In plan mode use ExitPlanMode; otherwise ask once with
   AskUserQuestion. Skip only if the user passed `--go` or said to start without asking.
5. **Launch the orchestrator** (from the run dir):
   ```
   cd <run-dir> && claude --bg -n <slug>-orch --model opus --effort medium --permission-mode auto \
     "/orchestrate run <run-dir>"
   ```
   Every job `cwd` and the run dir must be inside a **trusted workspace** (`claude --bg` refuses otherwise with
   "Workspace not trusted"); `~/Documents/...` is trusted. Check this before launching; if a cwd isn't trusted, ask the
   user to run `claude` there once and accept the prompt.
   Tell the user how to follow it: `claude agents`, `claude attach <slug>-orch`, `<run-dir>/ORCHESTRATOR.md`,
   `~/.claude/skills/orchestrate/scripts/orch-status <run-dir>`, and that answers to questions can be given by attaching
   to the orchestrator or by writing `<run-dir>/jobs/<job>/answer.md`.

---

## Run mode (`/orchestrate run <run-dir>`, the orchestrator session)

1. **Bootstrap (E0).** Read `PLAN.md`, `TASK.md`, `IMPLEMENTER.md`, `VERIFIER.md`. Create `ORCHESTRATOR.md` (queue,
   slots, gates, pending decisions, log) and `jobs/<job>/status.json` (`state: queued`) for every job. Check
   preconditions the plan names (auth scopes, tools, disk). If a resumed run: trust `status.json` + `handoff.md` files,
   reconcile with `orch-status`, never relaunch a job that is live.
2. **Start the loop:** invoke the `loop` skill with `3m Run one orchestrator tick for <run-dir> per the orchestrate skill
   references/tick.md`. Then run the first tick immediately.
3. **Each tick:** follow `references/tick.md` exactly. Keep tick output to a few lines; all state lives in files.
4. **Finish:** when the e2e verify job PASSes and no gate is open: write `<run-dir>/REPORT.md` (what was done, where it
   lives, verification evidence, open items), schedule any delayed checks the plan asks for, stop the loop, and end with a
   `result:` line. If the task proves impossible, write `failed:` with the reason.

### Non-negotiables for the orchestrator
- Never approve a permission prompt or make a gated decision on the user's behalf. Pause that session.
- **Sequential, blocking escalation.** Phases run strictly in order: a phase starts only when every job of the previous
  phase is implemented AND verified and no pending decision is open. While the user owes anything (access, a decision,
  a manual action), sessions already running in the current phase may finish, but nothing from a later phase launches,
  not even in a "prepare-only" mode. When a phase ends with human-needed items, escalate and pause the loop (stop
  ticking until the user answers); resume only after the items are confirmed done and the phase verifies end to end.
  Why: the user wants to implement and verify everything sequentially (2026-10-14).
- Never exceed the session cap. Blocked sessions are stopped (`claude stop`) so they don't hold a slot.
- Never let anything outward-facing happen before its verifier PASSes.
- Do no implementation yourself; read-only checks are fine.
- Relay the user's answers verbatim into `answer.md`, then resume the session.
