---
name: repo-tidy
description: Merge chosen branches into the default branch through PRs, sync default checkouts, and remove merged worktrees, branches and stale Claude state across $AGENTS_ROOT (or named repos). Deletions run through bin/repo-tidy, which deletes only verified-merged work and bundles every ref first.
disable-model-invocation: true
argument-hint: "[repo ...] [merge <branch|all> ...] [--remote] [--claude-state]"
---

# repo-tidy

Invoking this skill authorizes: `git fetch`, fast-forwarding clean default checkouts, and removing worktrees and local
branches that `repo-tidy` proves are merged (it bundles them first). It authorizes merging **only** the branches named
after `merge` in the arguments (`all` = every unmerged branch the dry run lists), deleting branches on origin **only**
with `--remote`, and archiving Claude state **only** with `--claude-state`. Anything else is a question to the user.

The deterministic work lives in `repo-tidy` (`~/.local/bin`, source `claude-code-fleet/bin/repo-tidy`, tests in
`tests/repo-tidy.bats`). Never re-implement its deletions by hand.

## Steps

1. **Scan (read-only).** `repo-tidy [repos] [--remote] [--claude-state]`. Show the user the non-trivial lines as a compact
   table grouped by action: `would:` (safe, will run), `decide:` (needs a choice), `keep` (left alone and why).
   `fetch-failed` repos are report-only: nothing is deleted from them.
2. **Pick merges.** Merge candidates are `unmerged(N)` branches and worktrees. If the arguments named none and the user
   didn't say "all", ask once with AskUserQuestion (multiSelect, one option per branch: `repo:branch, N commits, last
   commit date`). Unselected branches stay as they are.
3. **Merge each selected branch**, one at a time, following the repo's own `CLAUDE.md` where it is stricter:
   - Work where the branch is checked out (its worktree) or in a fresh `git worktree add`; never in a dirty checkout.
     Uncommitted changes in a selected worktree: commit them only if they are clearly part of that branch's work,
     otherwise stop with `needs input:`. Never stash, reset, `checkout --` or discard anything.
   - `git fetch origin && git rebase origin/<default>`; resolve conflicts only when intent is obvious, else
     `git rebase --abort` and stop with `needs input:` listing the files. Run the repo's tests/lint if it has them.
   - GitHub remote: `git push -u origin <branch>` (plain push; `--force-with-lease` only on a branch that only this
     merge uses, after the rebase), reuse an open PR or `gh pr create --fill`, wait for `gh pr checks <n> --watch`, then
     `gh pr merge <n> --squash --delete-branch`. Failing checks, required reviews or branch protection: stop and report
     the PR link; never `--admin`, never bypass. If the repo requires draft PRs or human review, open the PR and stop there.
   - No GitHub remote (or no remote): in the default checkout (clean, on the default branch)
     `git merge --ff-only <branch>`, then `git push origin <default>` if there is an origin.
4. **Clean up.** `repo-tidy --apply [repos] [--remote] [--claude-state]`, with the same flags as step 1. Any `FAILED:`
   line is reported verbatim; do not retry it with force.
5. **Verify and report.** Re-run the dry run. Report: PRs merged (links), what was removed (from the `done:` lines), what
   was kept and why, the backup dir from the `backups:` line, and the `decide:` items still open. End with a
   `result:` line.

## Never
- Force-push a shared branch, push to a default branch except a fast-forward in step 3, or merge with a merge commit
  outside a PR.
- `git branch -D`, `git worktree remove --force`, `rm -rf` of a worktree, or editing `~/.claude.json` /
  `~/.claude/projects` by hand. If `repo-tidy` keeps something, report it as kept.
- Touch a repo that is mid-merge/rebase, a locked worktree, or a worktree a process is using.

## Restore
Each run that deletes refs writes `$REPO_TIDY_STATE/<timestamp>/` (default `~/.local/state/repo-tidy/`): `<repo>.refs`
lists `sha ref bundle`; restore with `git -C <repo> fetch <bundle> <ref>:<ref>`. Archived Claude project dirs are in
`claude-projects/`, the pre-change `~/.claude.json` is `claude.json`.
