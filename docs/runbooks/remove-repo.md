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
ssh cloud 'rm -rf /data/fleet/<repo>'          # or on the Mac: rm -rf ~/Documents/<repo>
```
Agent View's `@` list drops it automatically.
