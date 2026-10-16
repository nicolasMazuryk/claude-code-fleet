# PLAN.md template (orchestration plan)

Keep it scannable. Reference the source plan's sections instead of copying them.

```markdown
# <Title>: orchestrated execution

## Context
Why, what the outcome is, source plan/task (path or TASK.md), binding rules (user CLAUDE.md, task overrides,
e.g. "pushing to default branch authorized by source §0").

## Settings
slug: <slug> · run dir: <dir> · orchestrator: opus/medium · implementers+verifiers: sonnet/medium ·
max sessions: 8 · tick: 3m · compact at: 250k · permission mode: auto

## Jobs
| Job | Scope (source refs) | cwd / isolation | Writes (owned) | Depends on | Gate | Acceptance checks | Verify | Fan-out hint |
|---|---|---|---|---|---|---|---|---|
| J00 <name> | … | <dir>, worktree `orch/<slug>/J00` | … | – | – | … | V / – | … |
| … |
| JNN integrate | merge branches in order, full suite | | | all code jobs | – | full suite green | – | – |
| JZZ e2e-verify | whole-task acceptance + REPORT inputs | | read-only | everything | – | … | – | per-area |

Queue order when a slot frees: verifiers first, then <J.. in order, critical path first>.

## Phases
- E0 Bootstrap (orchestrator only): run dir, preconditions, loop.
- E1 …: jobs …, exit gate …
- E2 …: parallel ≤ cap, refilled from queue …
- …
- En E2E verify → REPORT.md. (Delayed checks, if any: when and what.)

## Human gates
G1 … (job, what the user decides, what blocks on it). Ad-hoc: any implementer blocker or permission prompt.

## Verification
Per-job verifiers (what they check, before which risky step); final e2e criteria.
```

## Job card rules
- **Writes (owned)** must not overlap between jobs that can run at the same time.
- **Acceptance checks** are commands or observable facts, not adjectives ("`pnpm test --filter api` passes",
  "`gitleaks detect` clean", "README renders on GitHub").
- **Verify = V** for any job whose result becomes public/outward-facing or is hard to undo; the verifier runs
  *before* that step (the implementer stops at `ready_for_verify`).
- A job that only reads (drafts, research) still owns its output paths.
