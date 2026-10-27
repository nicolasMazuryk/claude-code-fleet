# Remove a repo

Status: Mac (Phase 3) and cloud (Phase 4b). Removing a *directory* deletes unpushed work — that step is always done by a human.

## Stop its Remote Control server (keep the clone)
1. Delete the line from `config/<host>/repos.txt`, commit (branch + PR).
2. Mac: `rc-servers` (closes window `rc:<repo>`). Cloud: `./install.sh cloud` (rsync + `rc-servers` disables
   `cc-rc@<repo>`).
3. Verify: Mac `tmux list-windows -t rc`; cloud `ssh cloud 'systemctl is-enabled cc-rc@<repo>'` → `disabled`.

## Delete the clone too (human)
```bash
ssh cloud 'git -C /data/fleet/<repo> worktree list; git -C /data/fleet/<repo> status --short'   # check for unpushed work
ssh cloud 'rm -rf /data/fleet/<repo>'          # or on the Mac: rm -rf ~/code/<repo>
```
Agent View's `@` list drops it automatically.

## Tidy merged worktrees and branches (every repo)
`/repo-tidy` (skill) merges the branches you pick through PRs, then runs `repo-tidy --apply`. The script alone:
```bash
repo-tidy                          # dry run over $AGENTS_ROOT: would/decide/keep per item
repo-tidy --apply --claude-state   # ff default checkouts; remove merged clean worktrees + merged branches; archive Claude state
repo-tidy --apply --remote <repo>  # also delete merged branches on origin (not ones with an open PR)
```
It keeps dirty, locked, in-use and unmerged work, and skips repos mid-merge/rebase or whose fetch fails. Every deleted
ref is bundled to `~/.local/state/repo-tidy/<ts>/` (`<repo>.refs` → `git fetch <bundle> <ref>:<ref>`).
