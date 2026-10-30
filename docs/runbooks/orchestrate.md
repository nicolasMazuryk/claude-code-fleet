# Orchestrate runs: follow and clean up

The `/orchestrate` skill lives in `config/claude/skills/orchestrate/` (applied to `~/.claude/skills/orchestrate/` by
`./install.sh mac`, mirrored to cloud by `make sync`). A run dir is `~/code/orchestrator-runs/<slug>/`; every
planner/implementer/verifier is a `claude --bg` session named `<slug>-[P-|V-|PV-]<job>[-r<n>]`.

## Follow a run
`S=~/.claude/skills/orchestrate/scripts`
- `$S/orchestrator-status <run-dir>`: orchestrator row, then one row per job (state, live, waiting-for, context).
- `claude attach <slug>-orchestrator`; `<run-dir>/ORCHESTRATOR.md` (Resume pointer, Log, Open items).

## Session cleanup
The orchestrator removes a job's sessions once the job is `done`, its verifier passed and its merge landed (tick
step 5), and runs `orchestrator-cleanup <run-dir> --all` before its `result:`. A handoff relaunch removes its stopped
predecessor right away. The orchestrator session itself is kept as the run's handle; remove it by hand with
`claude rm <id>` when the run is finished.

By hand (paused or abandoned run):
```bash
~/.claude/skills/orchestrate/scripts/orchestrator-cleanup ~/code/orchestrator-runs/<slug> --all --dry-run
~/.claude/skills/orchestrate/scripts/orchestrator-cleanup ~/code/orchestrator-runs/<slug> --all
```
- Only `done` jobs are touched (`skip <job>: state …` for the rest). `failed`/`blocked` jobs keep their sessions for
  inspection; remove them by hand once you have read them.
- Exit 3 (`refuse …`): a session is busy or waiting, or the recorded `merged_sha` is not on the default branch. Nothing
  was touched.
- Exit 4 (`kept <name>: …`): `claude rm` refused because the session's worktree has unpushed commits or uncommitted
  changes. The session is stopped (no process). The script never passes `--discard-unpushed` or
  `--force-remove-worktree`; push or inspect the work, then rerun, or pass the flag `claude rm` printed yourself.
- The script needs the run dir's `jobs/*/status.json`: without it no job can be shown to be `done`, so sessions of a
  deleted run dir are removed by hand (`claude agents --json --all`, then `claude rm <id>` per row).
- Rerunning prints `absent` for already-removed sessions and changes nothing.
