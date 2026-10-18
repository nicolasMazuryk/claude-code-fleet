#!/usr/bin/env bats
# cc-sync-settings.bats — the Mac → cloud settings transform (--print, no ssh) and the cloud cc-relay-hook queue.

setup() {
  REPO="$BATS_TEST_DIRNAME/.."
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.local/bin"
  for s in agent-env cc-sync-settings cc-relay-hook; do ln -s "$REPO/bin/$s" "$HOME/.local/bin/$s"; done
  export CC_ORCH_CONFIG="$BATS_TEST_TMPDIR/config" NVM_DIR="$BATS_TEST_TMPDIR/no-nvm"
  printf 'AGENT_HOST=mac\nAGENTS_ROOT=%s\nCC_ORCH_DIR=%s\n' "$HOME" "$REPO" > "$CC_ORCH_CONFIG"
  # the live Mac: captured baseline + orchestrator keys + agent-push groups + Mac-only bits that must not reach cloud
  F="$BATS_TEST_TMPDIR/settings.json"
  jq -s --arg home "$HOME" '(.[0] * .[1])
      | .hooks.Notification += [{hooks: [{type: "command", command: "~/.claude/hooks/agent-push.sh", async: true}]}]
      | .hooks.Stop += [{hooks: [{type: "command", command: "~/.claude/hooks/agent-push.sh", async: true}]}]
      | .enabledPlugins["warp@claude-code-warp"] = true
      | .env.GITHUB_TOKEN = "ghp_notreal" | .env.KEEP = "1"
      | .worktree.baseDir = ($home + "/Documents/x")' \
    "$REPO/config/claude/settings.mac.json" "$REPO/config/claude/settings.orchestrator.json" > "$F"
  export CC_SYNC_SRC="$F" CC_SYNC_CLOUD_HOME=/data/home/agent
}

sum() { printf %s "$1" | shasum -a 256 | cut -c1-16; }

@test "4 afplay handlers become hash-checked cc-relay-hook stand-ins at the same positions" {
  "$HOME/.local/bin/cc-sync-settings" --print > "$BATS_TEST_TMPDIR/out.json" 2> "$BATS_TEST_TMPDIR/err"
  grep -qx '4 macOS-only hook handler(s) relayed' "$BATS_TEST_TMPDIR/err"
  o="$BATS_TEST_TMPDIR/out.json"
  [ "$(jq '[.hooks[][].hooks[] | select(.command | test("afplay"))] | length' "$o")" -eq 0 ]
  [ "$(jq '[.hooks[][].hooks[] | select(.command | startswith("~/.local/bin/cc-relay-hook "))] | length' "$o")" -eq 4 ]
  for p in Stop:0:0 Notification:0:0 PreToolUse:0:0 StopFailure:0:0; do
    IFS=: read -r ev g h <<<"$p"
    orig=$(jq -r --arg e "$ev" ".hooks[\$e][$g].hooks[$h].command" "$CC_SYNC_SRC")
    [ "$(jq -r --arg e "$ev" ".hooks[\$e][$g].hooks[$h].command" "$o")" = "~/.local/bin/cc-relay-hook $ev $g $h $(sum "$orig")" ]
    [ "$(jq -r --arg e "$ev" ".hooks[\$e][$g].hooks[$h].async" "$o")" = true ]
  done
  # matchers kept, agent-push groups kept (they run on cloud too)
  [ "$(jq -r '.hooks.Notification[0].matcher' "$o")" = "permission_prompt|elicitation_dialog" ]
  [ "$(jq -r '.hooks.PreToolUse[0].matcher' "$o")" = "AskUserQuestion|ExitPlanMode" ]
  [ "$(jq '[.hooks[][].hooks[] | select(.command == "~/.claude/hooks/agent-push.sh")] | length' "$o")" -eq 2 ]
}

@test "Mac-only keys and credentials are dropped, home rewritten, cloud overrides win" {
  "$HOME/.local/bin/cc-sync-settings" --print > "$BATS_TEST_TMPDIR/out.json" 2>/dev/null
  o="$BATS_TEST_TMPDIR/out.json"
  [ "$(jq 'has("statusLine")' "$o")" = false ]
  [ "$(jq 'has("preferredNotifChannel")' "$o")" = false ]
  [ "$(jq '.enabledPlugins | has("warp@claude-code-warp")' "$o")" = false ]
  [ "$(jq -r '.enabledPlugins["claude-hud@claude-hud"]' "$o")" = true ]
  [ "$(jq '.env | has("GITHUB_TOKEN")' "$o")" = false ]
  [ "$(jq -r .env.KEEP "$o")" = 1 ]
  [ "$(jq -r .env.CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX "$o")" = cloud ]
  [ "$(jq -r .permissions.defaultMode "$o")" = auto ]
  [ "$(jq -r .worktree.baseDir "$o")" = /data/home/agent/Documents/x ]
  ! grep -q "$HOME" "$o"
  ! grep -q ghp_notreal "$o"
}

@test "the transform is deterministic (a second sync is a no-op)" {
  a=$("$HOME/.local/bin/cc-sync-settings" --print 2>/dev/null)
  b=$("$HOME/.local/bin/cc-sync-settings" --print 2>/dev/null)
  [ "$a" = "$b" ]
}

@test "refuses to run on cloud" {
  printf 'AGENT_HOST=cloud\nAGENTS_ROOT=/x\n' > "$CC_ORCH_CONFIG"
  run "$HOME/.local/bin/cc-sync-settings" --print
  [ "$status" -eq 2 ]
}

@test "cc-relay-hook queues event, position, hash and a trimmed payload" {
  long=$(printf 'x%.0s' $(seq 1 700))
  printf '{"hook_event_name":"Stop","last_assistant_message":"%s"}' "$long" |
    "$HOME/.local/bin/cc-relay-hook" Stop 0 0 abcdef0123456789
  f="$HOME/.local/state/agent-events/events.jsonl"
  [ "$(wc -l < "$f" | tr -d ' ')" -eq 1 ]
  [ "$(jq -r '[.event, .group, .handler, .sum] | @tsv' "$f")" = "$(printf 'Stop\t0\t0\tabcdef0123456789')" ]
  [ "$(jq -r '.payload.last_assistant_message | length' "$f")" -eq 500 ]
  printf 'not json' | "$HOME/.local/bin/cc-relay-hook" Notification 0 0 x
  [ "$(tail -n1 "$f" | jq -c .payload)" = '{}' ]
}

@test "the profile dir is mirrored to cloud with --delete" {
  mkdir -p "$HOME/.claude/profile"
  cp "$CC_SYNC_SRC" "$HOME/.claude/settings.json"
  echo '# me' > "$HOME/.claude/profile/me.md"
  # fake ssh (cloud has nothing yet) and rsync (records its arguments); agent-env puts ~/.local/bin first on PATH
  b="$HOME/.local/bin"
  printf '#!/bin/sh\nexit 0\n' > "$b/ssh"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/rsync.args"\n' "$BATS_TEST_TMPDIR" > "$b/rsync"
  chmod +x "$b/ssh" "$b/rsync"
  run "$HOME/.local/bin/cc-sync-settings" --dry-run
  [ "$status" -eq 0 ]
  grep -qx profile "$BATS_TEST_TMPDIR/rsync.args"
  grep -qx -- --delete "$BATS_TEST_TMPDIR/rsync.args"
  grep -qx cloud:.claude/ "$BATS_TEST_TMPDIR/rsync.args"
}
