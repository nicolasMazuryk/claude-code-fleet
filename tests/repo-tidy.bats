#!/usr/bin/env bats
# repo-tidy.bats — bin/repo-tidy against a scratch origin + clone: dry run changes nothing; --apply removes only merged,
# clean, unused worktrees and merged branches (bundled first); unmerged, dirty and unique-ignored work is kept.

setup() {
  T="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/bin/repo-tidy"
  export HOME="$BATS_TEST_TMPDIR/home" REPO_TIDY_STATE="$BATS_TEST_TMPDIR/state" AGENTS_ROOT="$BATS_TEST_TMPDIR/root"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"; git config --global init.defaultBranch main
  mkdir -p "$HOME/.claude/projects" "$AGENTS_ROOT"
  git init -q --bare "$BATS_TEST_TMPDIR/origin.git"
  R="$AGENTS_ROOT/r"; git clone -q "$BATS_TEST_TMPDIR/origin.git" "$R" 2>/dev/null; cd "$R"; R=$(pwd -P)
  printf 'node_modules/\n.env\nout.txt\n.claude/worktrees/\n' > .gitignore; echo 0 > f; echo SECRET=1 > .env
  git add .gitignore f && git commit -qm init && git push -q origin main && git remote set-head origin main
  # merged: fast-forwarded into main
  git switch -qc ff && echo ff > ff && git add ff && git commit -qm ff && git switch -q main && git merge -q --ff-only ff
  # squashed: two commits squash-merged into main
  git switch -qc sq && echo a > a && git add a && git commit -qm a && echo b > b && git add b && git commit -qm b
  git switch -q main && git merge -q --squash sq && git commit -qm squash
  git push -q origin main
  # unmerged branch and worktrees
  git switch -qc wip && echo w > w && git add w && git commit -qm wip && git switch -q main
  git worktree add -q .claude/worktrees/done -b done main~0 2>/dev/null
  mkdir -p .claude/worktrees/done/node_modules && cp .env .claude/worktrees/done/.env
  git worktree add -q .claude/worktrees/dirty -b dirty 2>/dev/null && echo x > .claude/worktrees/dirty/f
  git worktree add -q .claude/worktrees/notes -b notes 2>/dev/null && echo mine > .claude/worktrees/notes/out.txt
  git worktree add -q .claude/worktrees/gone -b gone 2>/dev/null && rm -rf .claude/worktrees/gone
  mkdir -p "$HOME/.claude/projects/$(printf '%s' "$R" | tr '/.' '--')--claude-worktrees-old"
  printf '{"projects":{"%s/.claude/worktrees/old":{},"%s":{"x":1}}}\n' "$R" "$R" > "$HOME/.claude.json"
  cd "$BATS_TEST_TMPDIR"
}

refs() { git -C "$R" for-each-ref --format='%(refname:short)' refs/heads | sort | tr '\n' ' '; }

@test "dry run reports and changes nothing" {
  before=$(refs)
  run "$T" --claude-state r
  [ "$status" -eq 0 ]
  [[ "$output" == *"branch:ff"*"would: git branch -D"* ]]
  [[ "$output" == *"branch:sq"*"merged"* ]]
  [[ "$output" == *"branch:wip"*"unmerged(1)"* ]]
  [[ "$output" == *"worktree:.claude/worktrees/dirty"*"dirty(1)"*"keep"* ]]
  [[ "$output" == *"worktree:.claude/worktrees/notes"*"unique ignored files: out.txt"* ]]
  [ "$(refs)" = "$before" ]
  [ -d "$R/.claude/worktrees/done" ]
  [ ! -d "$REPO_TIDY_STATE"/2* ]
}

@test "--apply removes merged work only, bundles every deleted ref, archives Claude state" {
  run "$T" --apply --claude-state r
  [ "$status" -eq 0 ]
  [ "$(refs)" = "dirty main notes wip " ]
  [ ! -d "$R/.claude/worktrees/done" ]
  [ -d "$R/.claude/worktrees/dirty" ] && [ -f "$R/.claude/worktrees/notes/out.txt" ]
  ! git -C "$R" worktree list | grep -q gone
  bk=$(echo "$REPO_TIDY_STATE"/2*)
  for b in ff sq done gone; do grep -q " refs/heads/$b " "$bk/r.refs" || { echo "no backup of $b"; return 1; }; done
  b=$(awk '/refs\/heads\/sq /{print $3}' "$bk/r.refs")
  git -C "$R" fetch -q "$b" refs/heads/sq:refs/heads/sq && [ "$(git -C "$R" log -1 --format=%s sq)" = b ]
  [ -d "$bk/claude-projects" ] && [ -f "$bk/claude.json" ]
  python3 -c 'import json,sys; p=json.load(open(sys.argv[1]))["projects"]; assert list(p)==[sys.argv[2]], p' "$HOME/.claude.json" "$R"
}

@test "--apply is idempotent and syncs a behind default checkout" {
  "$T" --apply r >/dev/null
  git clone -q "$BATS_TEST_TMPDIR/origin.git" "$BATS_TEST_TMPDIR/other" 2>/dev/null
  (cd "$BATS_TEST_TMPDIR/other" && echo 2 > f && git commit -qam two && git push -q origin main)
  run "$T" --apply r
  [[ "$output" == *"checkout:main"*"behind(1)"*"done: pull --ff-only"* ]]
  [ "$(git -C "$R" log -1 --format=%s main)" = two ]
  run "$T" --apply r
  [[ "$output" != *"done:"* ]]
}

@test "a worktree used as some process's cwd is kept" {
  (cd "$R/.claude/worktrees/done" && sleep 30) & pid=$!
  sleep 0.5
  run "$T" --apply r
  kill "$pid" 2>/dev/null || true
  [[ "$output" == *"worktree:.claude/worktrees/done"*"in-use-by-a-process"* ]]
  [ -d "$R/.claude/worktrees/done" ]
}

@test "--remote deletes merged origin branches only" {
  git -C "$R" push -q origin ff wip
  run "$T" --apply --remote r
  [[ "$output" == *"remote:ff"*"done: git push origin --delete"* ]]
  [[ "$output" == *"remote:wip"*"unmerged"*"keep"* ]]
  [ -z "$(git -C "$R" ls-remote --heads origin ff)" ] && [ -n "$(git -C "$R" ls-remote --heads origin wip)" ]
}

@test "a repo mid-rebase is skipped" {
  mkdir "$R/.git/rebase-merge"
  run "$T" --apply r
  [[ "$output" == *"merge/rebase-in-progress"*"skip repo"* ]]
  [ -d "$R/.claude/worktrees/done" ]
}
