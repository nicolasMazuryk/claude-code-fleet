# Orchestrate runs: follow and clean up

The `/orchestrate` skill lives in `config/claude/skills/orchestrate/` (applied to `~/.claude/skills/orchestrate/` by
`./install.sh mac`, mirrored to cloud by `make sync`). A run dir is `~/code/orchestrator-runs/<slug>/`; every
planner/implementer/verifier is a `claude --bg` session named `<slug>-[P-|V-|PV-]<job>[-r<n>]`.

## Follow a run
`S=~/.claude/skills/orchestrate/scripts`
- `$S/orchestrator-status <run-dir>`: orchestrator row, then one row per job (state, live, waiting-for, context).
- `claude attach <slug>-orchestrator`; `<run-dir>/ORCHESTRATOR.md` (Resume pointer, Log, Open items).

## Session cleanup
Sessions are removed continuously during the run, not at the end: every tick runs the sweep
`orchestrator-cleanup <run-dir> --all` (tick step 6), which stops and removes each session whose status id is `done`
and whose state is already in run-dir files. Live processes therefore track active work, even on a 20–30 job run.

| Session | Removed when | State kept in |
|---|---|---|
| planner `P-<job>` | the plan is taken (`P-<job> done`) | `plan.md` / `plan-draft.md` |
| plan review `PV-<job>` | plan-review.md written (`PV-<job> done`) | `plan-review.md` |
| verifier `V-<job>` | verify-report.md written (`V-<job> done`), even while the job still runs | `verify-report.md` |
| implementer `<job>` | job `done` and its `merged_sha` is on the default branch | `handoff.md`, the repo |
| handoff predecessor | its successor is live (tick step 3) | `handoff.md` etc. |

A relaunch under a `done` id (re-verify after a FAIL, Revise planner) resets it to `running`, so the sweep never
removes the new session. The orchestrator session itself is kept as the run's handle; remove it by hand with
`claude rm <id>` when the run is finished.

By hand (paused or abandoned run):
```bash
~/.claude/skills/orchestrate/scripts/orchestrator-cleanup ~/code/orchestrator-runs/<slug> --all --dry-run
~/.claude/skills/orchestrate/scripts/orchestrator-cleanup ~/code/orchestrator-runs/<slug> --all
```
- One id by hand: `orchestrator-cleanup <run-dir> V-J03` (that role only) or `<run-dir> J03` (the whole family).
- Only `done` ids are touched (`skip <id>: state …` for the rest). `failed`/`blocked` ids keep their sessions for
  inspection; remove them by hand once you have read them.
- `refuse …`: a session is busy or waiting, or the recorded `merged_sha` is not on the default branch; that id was not
  touched. Single-id mode exits 3; the `--all` sweep prints it and exits 0 (retried next tick).
- Exit 4 (`kept <name>: …`): `claude rm` refused because the session's worktree has unpushed commits or uncommitted
  changes. The session is stopped (no process). The script never passes `--discard-unpushed` or
  `--force-remove-worktree`; push or inspect the work, then rerun, or pass the flag `claude rm` printed yourself.
- The script needs the run dir's `jobs/*/status.json`: without it no job can be shown to be `done`, so sessions of a
  deleted run dir are removed by hand (`claude agents --json --all`, then `claude rm <id>` per row).
- Rerunning prints `absent` for already-removed sessions and changes nothing.
