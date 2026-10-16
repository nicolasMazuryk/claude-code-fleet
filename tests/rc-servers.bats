#!/usr/bin/env bats
# rc-servers.bats — Mac reconcile of tmux session "rc" against repos.txt, and repo-init setup files / --rc.
# Uses a private tmux socket (TMUX_TMPDIR) and a stub rc-serve, so no real claude process starts.

setup() {
  command -v tmux >/dev/null || skip "tmux not installed"
  REPO="$BATS_TEST_DIRNAME/.."
  export HOME="$BATS_TEST_TMPDIR/home" TMUX_TMPDIR="$BATS_TEST_TMPDIR/tmux"
  unset TMUX
  mkdir -p "$HOME/.local/bin" "$HOME/root" "$TMUX_TMPDIR"
  for s in agent-env rc-servers repo-init; do ln -s "$REPO/bin/$s" "$HOME/.local/bin/$s"; done
  printf '#!/bin/sh\nexec sleep 600\n' > "$HOME/.local/bin/rc-serve"; chmod +x "$HOME/.local/bin/rc-serve"
  export CC_ORCH_CONFIG="$BATS_TEST_TMPDIR/config" NVM_DIR="$BATS_TEST_TMPDIR/no-nvm"
  printf 'AGENT_HOST=mac\nAGENTS_ROOT=%s\nAGENTS_SESSION=agents\nREPOS_FILE=%s\n' \
    "$HOME/root" "$BATS_TEST_TMPDIR/repos.txt" > "$CC_ORCH_CONFIG"
  for r in a b c; do git init -q "$HOME/root/$r"; done
  printf '# comment\na\n  b   # trailing\n' > "$BATS_TEST_TMPDIR/repos.txt"
}

teardown() { tmux kill-server 2>/dev/null || true; }

windows() { tmux list-windows -t '=rc' -F '#W' | sort | tr '\n' ' '; }

@test "rc-servers opens one window per listed repo, idempotently" {
  run "$HOME/.local/bin/rc-servers"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(windows)" = "a b idle " ]
  run "$HOME/.local/bin/rc-servers"
  [ -z "$output" ]
  [ "$(windows)" = "a b idle " ]
}

@test "rc-servers closes windows of repos removed from the list and skips non-repos" {
  "$HOME/.local/bin/rc-servers"
  printf 'b\nmissing\n' > "$BATS_TEST_TMPDIR/repos.txt"
  run "$HOME/.local/bin/rc-servers"
  [[ "$output" == *"skip missing"* ]]
  [ "$(windows)" = "b idle " ]
}

@test "repo-init writes setup files once and --rc appends to the allowlist once" {
  run "$HOME/.local/bin/repo-init" --rc --no-trust c
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  run "$HOME/.local/bin/repo-init" --rc --no-trust c
  [ "$status" -eq 0 ]
  [ "$(grep -cx '.claude/worktrees/' "$HOME/root/c/.gitignore")" -eq 1 ]
  [ "$(grep -cx '.env' "$HOME/root/c/.worktreeinclude")" -eq 1 ]
  [ "$(grep -cx '.env.local' "$HOME/root/c/.worktreeinclude")" -eq 1 ]
  [ "$(grep -cx 'c' "$BATS_TEST_TMPDIR/repos.txt")" -eq 1 ]
  [[ "$(windows)" == *"c"* ]]
}

@test "repo-init keeps the last line of a .gitignore without a trailing newline" {
  printf 'archive/\nbacklog/' > "$HOME/root/c/.gitignore"
  printf 'a' > "$BATS_TEST_TMPDIR/repos.txt"
  run "$HOME/.local/bin/repo-init" --rc --no-trust c
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$HOME/root/c/.gitignore")" = "$(printf 'archive/\nbacklog/\n.claude/worktrees/')" ]
  [ "$(cat "$BATS_TEST_TMPDIR/repos.txt")" = "$(printf 'a\nc')" ]
}

@test "repo-init without --rc does not start a server" {
  run "$HOME/.local/bin/repo-init" --no-trust c
  [ "$status" -eq 0 ]
  [[ "$output" == *"no RC server"* ]]
  ! tmux has-session -t '=rc' 2>/dev/null
}
