---
name: merge-worktree
description: Merge the current worktree's branch into the default branch, push, update the main checkout, then remove that worktree and its branch. Only the current worktree; other worktrees are never touched.
disable-model-invocation: true
---

# merge-worktree

Invoking this command is the user's authorization to commit, push the default branch and delete the current worktree and its branch. It covers only the worktree the session is in now.

## Steps

1. **Identify.** From the worktree, record `WT=$(git rev-parse --show-toplevel)`, `BR=$(git branch --show-current)`, the main checkout `MAIN=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")` and the default branch `DEF=$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's@^origin/@@')` (fall back to `main`). Stop with `failed:` if the session is not in a linked worktree (`$WT` equals `$MAIN`) or `$BR` is the default branch.
2. **Commit leftovers.** `git status --short`. Commit any uncommitted changes with a descriptive message (plus the session's attribution lines) and tell the user what they were. Skip junk that clearly shouldn't be committed (build output, secrets) and say so.
3. **Bring the branch up to date.** `git fetch origin`, then `git rebase origin/$DEF`. On conflicts, resolve them if the intent is obvious; otherwise `git rebase --abort` and stop with `needs input:` listing the conflicting files.
4. **Leave the worktree.** Call `ExitWorktree` with `action: "keep"` if the session entered the worktree with `EnterWorktree` (this is required: the isolation guard blocks git commands aimed at the shared checkout from inside a worktree). Otherwise run the remaining steps with `cd "$MAIN"`.
5. **Merge in the main checkout.** In `$MAIN`:
   - `git status --short` must be empty and `git branch --show-current` must be `$DEF`. If not, stop with `needs input:`. Never stash, reset or discard the user's changes.
   - `git pull --ff-only origin $DEF`
   - `git merge --ff-only $BR`, then `git push origin $DEF`.
6. **Clean up the worktree and branch.**
   - `git worktree unlock "$WT" 2>/dev/null; git worktree remove "$WT"`. If it refuses because of untracked or ignored files, list them (`git -C "$WT" status --short --ignored`). Use `--force` only when they are disposable (caches, `node_modules`, build output); otherwise stop with `needs input:`.
   - `git branch -d $BR` (never `-D` on unmerged work), then `git push origin --delete $BR` if `git ls-remote --heads origin $BR` shows it exists.
   - `git worktree prune`.
7. **Report.** Give the commits merged (`git log --oneline origin/$DEF -n <count>`), confirm that local `$DEF` equals `origin/$DEF` (`git status -sb`), and show `git worktree list`. End with a `result:` line.

## Never
- Touch any other worktree or branch.
- Force-push, or push anything except `$DEF` and the branch deletion.
- Create a merge commit. If a fast-forward isn't possible after step 3, stop and report it.
