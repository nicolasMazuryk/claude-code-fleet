# PLAN.md template (orchestration plan)

Keep it scannable. Reference the source plan's sections instead of copying them.

```markdown
# <Title>: orchestrated execution

## Context
Why, what the outcome is, source plan/task (path or TASK.md), binding rules (user CLAUDE.md, task overrides,
e.g. "pushing to default branch authorized by source §0").

## Settings
slug: <slug> · run dir: <dir> · orchestrator: opus/medium · implementers+verifiers: sonnet/medium ·
max sessions: 8 · tick: 3m · compact at: 200k · permission mode: auto

## Dependency graph
Edges (`A → B` = B needs A done and verified), one per line, with the kind (data / interface / build / knowledge):
- J00 → J01 (interface: J01 consumes the API types J00 defines)
- …
Critical path: J00 → J01 → J04 → JNN → JZZ.

## Jobs
| Job | Scope (source refs) | cwd / isolation | Writes (owned) | Depends on | Parallel with / why safe | Gate | Acceptance checks | Verify | Fan-out hint |
|---|---|---|---|---|---|---|---|---|---|
| J00 <name> | … | <dir>, worktree `orchestrator/<slug>/J00` | … | – | – (foundation, runs alone) | – | … | V | … |
| J01 <name> | … | … | … | J00 | J02: disjoint dirs, no shared ports/DB, both consume frozen J00 contract | – | … | – | … |
| … |
| JI1 integrate-S2 | merge S2 branches in order, full suite | | | S2 jobs | – | – | full suite green | – | – |
| JNN integrate | final merge, full suite | | | all code jobs | – | – | full suite green | – | – |
| JZZ e2e-verify | whole-task acceptance + REPORT inputs | | read-only | everything | – | – | … | – | per-area |

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
