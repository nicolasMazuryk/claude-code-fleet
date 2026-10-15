---
name: update-autoresearch-worktrees
description: Merge latest main into all datapipeline autoresearch git worktrees (merge, never rebase). Use after main gets new autoresearch/strategy/backtest commits.
---

# Update Autoresearch Worktrees

Merge the latest main branch into all autoresearch git worktrees for the datapipeline project.

## When to use

Run this after main branch has received new commits that need to propagate into the autoresearch experiment worktrees — typically after merging PRs that update autoresearch source code, strategy configs, program.md, or the backtesting engine.

## Critical constraint: never rebase

Autoresearch tracks iteration state via commit hashes stored in `.autoresearch/results/<tag>/state.json` (`best_commit`, `last_keep_commit`, `baseline_commit`) and `.autoresearch/results/<tag>/results.tsv` (`commit_hash` column). Rebasing rewrites hashes and breaks state reconciliation. **Always use `git merge`, never `git rebase`.**

## Execution

Run the following bash script. It auto-discovers all worktrees under `.autoresearch/worktrees/` so it works regardless of how many worktrees exist or what they're named.

```bash
set -euo pipefail

REPO="$(git rev-parse --show-toplevel)"
WORKTREES_DIR="$REPO/.autoresearch/worktrees"

if [ ! -d "$WORKTREES_DIR" ]; then
  echo "No worktrees directory found at $WORKTREES_DIR — nothing to do."
  exit 0
fi

for worktree_dir in "$WORKTREES_DIR"/*/; do
  [ -d "$worktree_dir" ] || continue
  tag=$(basename "$worktree_dir")
  echo ""
  echo "════════════════════════════════════════"
  echo "  $tag"
  echo "════════════════════════════════════════"

  cd "$worktree_dir"

  # Skip if this worktree already contains all of main
  if git merge-base --is-ancestor main HEAD 2>/dev/null; then
    echo "  Already up to date — skipping"
    continue
  fi

  # Attempt merge (auto-commits on success, stops on conflict)
  if git merge main --no-ff -m "Merge main into autoresearch/$tag" 2>&1; then
    echo "  ✓ Clean merge"
    continue
  fi

  # Conflict resolution
  echo "  Conflicts detected — resolving..."
  git diff --name-only --diff-filter=U | while IFS= read -r file; do
    if [[ "$file" == config/strategies/*.yaml ]]; then
      # Keep the worktree's agent-tuned parameter values
      git checkout --ours  "$file"
      git add "$file"
      echo "    [ours]   $file  (kept agent-tuned values)"
    else
      # All other files: take main's version
      git checkout --theirs "$file"
      git add "$file"
      echo "    [theirs] $file  (took main version)"
    fi
  done

  git commit --no-edit -m "Merge main into autoresearch/$tag"
  echo "  ✓ Resolved and committed"
done

echo ""
echo "All worktrees updated."
```

## Conflict resolution rules

| File pattern | Resolution | Reason |
|---|---|---|
| `config/strategies/*.yaml` | Keep **ours** (worktree) | Preserves agent-tuned parameter values from completed iterations |
| All other files | Keep **theirs** (main) | Takes updated source code, program.md, matrix.yaml, etc. |

## State file safety

`.autoresearch/results/<tag>/state.json` and `results.tsv` are gitignored — they are never touched by a merge. All commit hashes stored in those files remain valid because merging only creates a new commit on top of the worktree branch; it does not rewrite existing iteration commits.

## Verification (after running)

```bash
# 1. Confirm all worktrees are now on top of main
git worktree list | grep autoresearch/

# 2. Spot-check one worktree's log — merge commit should be on top, iter commits below
git -C .autoresearch/worktrees/<tag> log --oneline -5

# 3. Confirm a worktree's state.json is unchanged
cat .autoresearch/results/<tag>/state.json

# 4. Confirm the stored best_commit is still a valid git object
best=$(python3 -c "import json; print(json.load(open('.autoresearch/results/<tag>/state.json'))['best_commit'])")
git cat-file -t $best   # should print: commit

# 5. Run autoresearch list to confirm all tags are recognized
npm run autoresearch:list
```
