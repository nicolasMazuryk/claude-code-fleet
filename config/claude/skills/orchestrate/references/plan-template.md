# PLAN.md template (orchestration plan)

Keep it scannable. Reference the source plan's sections instead of copying them.

```markdown
# <Title>: orchestrated execution

## Context
Why, what the outcome is, source plan/task (path or TASK.md), binding rules (user CLAUDE.md, task overrides,
e.g. "pushing to default branch authorized by source §0").

## Settings
slug: <slug> · run dir: <dir> · max sessions: 8 · tick: 3m · compact at: 200k · permission mode: auto (planners: plan)
orchestrator: opus/medium · planner: sonnet/high · implementer: sonnet/medium · verifier: sonnet/medium

## Dependency graph
Edges (`A → B` = B needs A done and verified), one per line, with the kind (data / interface / build / knowledge):
- J00 → J01 (interface: J01 consumes the API types J00 defines)
- …
Critical path: J00 → J01 → J04 → JNN → JZZ.

## Jobs
| Job | Scope (source refs) | cwd / isolation | Writes (owned) | Depends on | Parallel with / why safe | Gate | Acceptance checks | Verify | Plan first | Fan-out hint |
|---|---|---|---|---|---|---|---|---|---|---|
| J00 <name> | … | <dir>, worktree `orchestrator/<slug>/J00` | … | – | – (foundation, runs alone) | – | … | V | yes+review | … |
| J01 <name> | … | … | … | J00 | J02: disjoint dirs, no shared ports/DB, both consume frozen J00 contract | – | … | – | yes | … |
| … |
| JI1 integrate-S2 | merge S2 branches in order, full suite | | | S2 jobs | – | – | full suite green | – | no | – |
| JNN integrate | final merge, full suite | | | all code jobs | – | – | full suite green | – | no | – |
| JZZ e2e-verify | whole-task acceptance + REPORT inputs | | read-only | everything | – | – | … | – | no | per-area |

Queue order when a slot frees: verifiers first, then launchable jobs in critical-path order.

## Stages
- E0 Bootstrap (orchestrator only): run dir, preconditions, loop.
- S1 Foundations: J00 (alone). Exit: J00 verified.
- S2 …: J01 ∥ J02 (parallel-safe, see cards), then JI1. Exit: JI1 green.
- S3 …: J03 (sequential: depends on J01's findings).
- …
- Sn E2E verify → REPORT.md. (Delayed checks, if any: when and what.)

## Human gates
G1 … (job, what the user decides, which downstream jobs it holds). Ad-hoc: any implementer blocker or permission
prompt holds that job's dependents.

## Verification
Per-job verifiers (what they check, before which risky step or which dependents); final e2e criteria.

## Job plan sections
Every `jobs/<job>/plan.md` written by a planner contains these sections; the orchestrator's plan check enforces them.
Target length 2–5k tokens.
1. Goal and acceptance checks.
2. Approach and why.
3. Steps: numbered, each with its files and commands.
4. Write set: exact paths, branches and remote resources.
5. Runtime resources: ports, databases, caches, toolchains, paid or rate-limited APIs.
6. Risks and mitigations.
7. Test commands.
8. Deviations from the card: empty, or each one justified.
9. Open questions.
```

## Job card rules
- **Writes (owned)** must not overlap between jobs in the same stage.
- **Parallel with / why safe** names each job it may run alongside and states how all five parallel-safety conditions
  hold (SKILL.md). Blank or uncertain → the job runs alone or after the other.
- **Depends on** lists every dependency edge; a job never starts before its dependencies are done and verified.
- **Acceptance checks** are commands or observable facts, not adjectives ("`pnpm test --filter api` passes",
  "`gitleaks detect` clean", "README renders on GitHub").
- **Verify = V** for any job whose result becomes public/outward-facing or is hard to undo, and for foundation jobs
  others build on; the verifier runs *before* that step or before dependents start (the implementer stops at
  `ready_for_verify`).
- A job that only reads (drafts, research) still owns its output paths.
- **Plan first** decides whether a plan-mode planner session writes `jobs/<job>/plan.md` before a fresh implementer
  starts. Planning costs about 5–10 minutes per job.
  - `no`: small or mechanical jobs (about 5 minutes or less, a few files, or a card that is already step by step),
    integration jobs and e2e-verify jobs. No planner runs.
  - `yes`: every other non-trivial job.
  - `yes+review`: jobs others depend on, and jobs with Verify = V. A plan-review verifier checks the plan before the
    implementer starts.
