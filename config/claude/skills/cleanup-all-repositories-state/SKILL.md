---
name: cleanup-all-repositories-state
description: Clean up every repo you own (origin github.com/nicolasMazuryk) under ~/code (recursive) or used by Claude Code. Shows a dry-run plan, asks once, merges only the branches you pick (through PRs), then syncs default branches and removes merged worktrees, local and origin branches, and stale Claude state. Organization repos are never touched. No arguments.
disable-model-invocation: true
---

# cleanup-all-repositories-state

Takes no arguments. The deterministic work lives in `repo-tidy` (`~/.local/bin`, source `claude-code-fleet/bin/repo-tidy`,
tests in `tests/repo-tidy.bats`). It discovers repos itself: every git repo under `$AGENTS_ROOT` (recursive), every
Claude Code project path in `~/.claude.json`, and every running session's cwd (`claude agents`). It handles only
repos whose origin is `github.com/nicolasMazuryk/…` and lists the rest as excluded. Never run git cleanup commands
against an excluded repo, and never re-implement the script's deletions by hand.

## Steps

1. **Dry run.** `repo-tidy` (no flags; it takes about 1–2 min). Show the plan as a compact table grouped by action:
   - `would:` will run on apply (fast-forward, remove a merged worktree, delete a merged local or origin branch, archive
     Claude state);
   - `decide:` needs a choice (unmerged branches, a default checkout ahead of origin or on another branch);
   - `keep`: left alone, with the reason (dirty, locked, in use, unique ignored files, fetch failed).
   Then the `excluded` line, shortened to a count plus names.
   If there are no `would:` and no `decide: merge` lines, report "nothing to do" and stop.
2. **Ask once** with AskUserQuestion:
   - "Apply this cleanup?": `Apply (Recommended)` / `Cancel`.
   - Only if the plan has unmerged branches: "Merge any unmerged branches first?": `None (Recommended)`,
     `All listed`, `Let me pick` (the user names `repo:branch` in Other). List them in the question text.
   Cancel: stop, nothing changed.
3. **Merge the chosen branches**, one at a time, following the repo's own `CLAUDE.md` where it is stricter:
   - Work where the branch is checked out (its worktree) or in a fresh `git worktree add`; never in a dirty checkout.
     Uncommitted changes in that worktree: commit them only if they clearly belong to the branch's work, otherwise skip
     the branch and report it. Never stash, reset, `checkout --` or discard anything.
   - `git fetch origin && git rebase origin/<default>`; resolve conflicts only when the intent is obvious, else
     `git rebase --abort`, skip the branch and report the files. Run the repo's tests/lint if it has them.
   - `git push -u origin <branch>` (`--force-with-lease` only on that branch, after the rebase), reuse an open PR or
     `gh pr create --fill`, wait for `gh pr checks <n> --watch`, then `gh pr merge <n> --squash --delete-branch`.
     Failing checks, required reviews or branch protection: skip and report the PR link. Never `--admin`. If the repo
     requires draft PRs or human review, open the PR and leave it.
4. **Apply.** `repo-tidy --apply`. Report every `FAILED:` line verbatim; never retry with force.
5. **Verify and report.** Run `repo-tidy` again. Report: PRs merged (links), what was removed (`done:` lines,
   summarized per repo), what was kept and why, the `backups:` path, and the `decide:` items still open. End with a
   `result:` line.

## Never
- Touch a repo `repo-tidy` lists as excluded (organization repos such as aleph1 or fio, or repos with no
  nicolasMazuryk origin).
- Force-push a shared branch, push to a default branch, or merge outside a PR.
- `git branch -D`, `git worktree remove --force`, `rm -rf` of a worktree, or editing `~/.claude.json` /
  `~/.claude/projects` by hand. If `repo-tidy` keeps something, report it as kept.

## Restore
Each run that deletes refs writes `~/.local/state/repo-tidy/<timestamp>/`. `<repo>.refs` lists `sha ref bundle`; restore
with `git -C <repo> fetch <bundle> <ref>:<ref>`, and for an origin branch push it back. Archived Claude project dirs
are in `claude-projects/`, and the pre-change `~/.claude.json` is `claude.json`.
