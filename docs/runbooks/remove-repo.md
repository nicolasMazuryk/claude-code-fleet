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

## Tidy merged worktrees and branches (all your repos)
`/cleanup-all-repositories-state` (skill, no arguments) shows the dry-run plan, asks once, merges any branches you pick
through PRs, then runs `repo-tidy --apply`. The script alone:
```bash
repo-tidy           # dry run: your repos under $AGENTS_ROOT (recursive) + repos Claude Code uses; would/decide/keep per item
repo-tidy --apply   # ff default checkouts; remove merged clean worktrees, merged local + origin branches; archive stale Claude state
```
Only repos whose origin is `github.com/$GH_OWNER` (nicolasMazuryk) are handled; organization and remote-less repos are
listed as excluded. It keeps dirty, locked, in-use and unmerged work, origin branches with an open PR, and skips repos
mid-merge/rebase or whose fetch fails. Every deleted ref is bundled to `~/.local/state/repo-tidy/<ts>/`
(`<repo>.refs` → `git fetch <bundle> <ref>:<ref>`). `--no-remote` / `--no-claude-state` narrow it.
