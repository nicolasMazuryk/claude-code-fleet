#!/usr/bin/env bats
# cc-capture.bats — sanitizing transform, secret abort, idempotence and mirroring of bin/cc-capture,
# against a fixture $HOME and a scratch copy of config/.

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  H="$BATS_TEST_TMPDIR/home"
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$H/.claude/sounds" "$H/.claude/skills/my-skill" "$H/.claude/plugins/claude-hud" \
           "$H/.config/ccstatusline" "$R/config/claude" "$R/config/mac"
  cat > "$H/.claude/settings.json" <<'EOF'
{
  "model": "opus",
  "env": { "GITHUB_TOKEN": "x", "OPENAI_API_KEY": "y", "FOO": "bar" },
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command", "command": "afplay ~/.claude/sounds/choo-choo.mp3" } ] },
      { "hooks": [ { "type": "command", "command": "~/.local/bin/agent-push.sh stop" } ] }
    ],
    "Notification": [
      { "matcher": "permission_prompt", "hooks": [ { "type": "command", "command": "afplay ~/.claude/sounds/choo-choo.mp3" } ] }
    ],
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "/x/hooks/agent-push.sh start" } ] }
    ]
  },
  "enabledPlugins": { "a@m": true }
}
EOF
  printf 'mp3' > "$H/.claude/sounds/choo-choo.mp3"
  printf '#!/bin/bash\necho hi\n' > "$H/.claude/statusline-combined.sh"
  chmod 700 "$H/.claude/statusline-combined.sh"
  printf -- '---\nname: my-skill\n---\n' > "$H/.claude/skills/my-skill/SKILL.md"
  echo '{}' > "$H/.claude/plugins/claude-hud/config.json"
  echo '{"plugins":{"a@m":[{"scope":"user","version":"1.0.0","projectPath":null}],"b@m":[{"scope":"project","version":"2","projectPath":"'"$H"'/Documents/x"}]}}' \
    > "$H/.claude/plugins/installed_plugins.json"
  echo '{"m":{"source":{"source":"github","repo":"o/m"},"installLocation":"/tmp"}}' > "$H/.claude/plugins/known_marketplaces.json"
  echo '{"version":4}' > "$H/.config/ccstatusline/settings.json"
  cat > "$H/.zshrc" <<'EOF'
export PATH=/x
alias unrelated=true

# Claude Code
alias c='claude'
export ANTHROPIC_API_KEY=abc
cw()  { claude --worktree "$@"; }

# Tailscale exit node
alias up="tailscale set --exit-node=1.2.3.4"
EOF
  export CC_CAPTURE_HOME="$H" CC_CAPTURE_REPO="$R"
}

cap() { run "$ROOT/bin/cc-capture" "$@"; }

@test "settings: credential env keys and agent-push handlers dropped, sound hooks kept" {
  cap
  [ "$status" -eq 0 ]
  s="$R/config/claude/settings.mac.json"
  [ "$(jq -c .env "$s")" = '{"FOO":"bar"}' ]
  [ "$(jq '[.hooks[][].hooks[] | select(.command | test("agent-push"))] | length' "$s")" -eq 0 ]
  [ "$(jq '[.hooks[][].hooks[] | select(.command | test("afplay"))] | length' "$s")" -eq 2 ]
  [ "$(jq '.hooks.Stop | length' "$s")" -eq 1 ]
  [ "$(jq '.hooks | has("SessionStart")' "$s")" = false ]
  [[ "$output" == *"GITHUB_TOKEN"*"OPENAI_API_KEY"* ]]
}

@test "files, skills, plugins and zsh blocks captured" {
  cap
  [ "$status" -eq 0 ]
  [ -x "$R/config/claude/statusline-combined.sh" ]
  [ -f "$R/config/claude/sounds/choo-choo.mp3" ]
  [ -f "$R/config/claude/skills/my-skill/SKILL.md" ]
  [ -f "$R/config/claude/plugins/claude-hud/config.json" ]
  [ -f "$R/config/claude/ccstatusline/settings.json" ]
  grep -q $'^my-skill\tlocal' "$R/config/claude/skills.txt"
  p="$R/config/claude/plugins.json"
  [ "$(jq -r '.marketplaces.m.repo' "$p")" = o/m ]
  [ "$(jq -r '.marketplaces.m | has("installLocation")' "$p")" = false ]
  [ "$(jq -r '.plugins[] | select(.id=="b@m") | .project' "$p")" = "~/Documents/x" ]
  [ "$(jq -r '.plugins[] | select(.id=="a@m") | .enabled' "$p")" = true ]
  z="$R/config/mac/zshrc.captured"
  grep -q "alias c='claude'" "$z"
  grep -q 'export ANTHROPIC_API_KEY=<redacted>' "$z"
  grep -q 'tailscale set' "$z"
  ! grep -q unrelated "$z"
  ! grep -q abc "$z"
}

@test "idempotent: second run changes nothing, --check is clean" {
  cap
  [ "$status" -eq 0 ]
  cap
  [[ "$output" == *"no changes"* ]]
  cap --check
  [ "$status" -eq 0 ]
  echo 'alias ca="claude agents"' >> "$H/.zshrc"
  sed -i '' 's/alias c=/alias cx=/' "$H/.zshrc" 2>/dev/null || sed -i 's/alias c=/alias cx=/' "$H/.zshrc"
  cap --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"differs: config/mac/zshrc.captured"* ]]
}

@test "secret-looking content aborts before writing anything" {
  echo "curl -d hi https://ntfy.sh/$(printf %032d 0)" >> "$H/.claude/statusline-combined.sh"
  cap
  [ "$status" -eq 1 ]
  [[ "$output" == *"secret-looking content"*"statusline-combined.sh"* ]]
  [ ! -e "$R/config/claude/settings.mac.json" ]
}

@test "deleted skills are removed; repo-only CLAUDE.md is kept" {
  cap
  echo "repo rules" > "$R/config/claude/CLAUDE.md"
  rm -r "$H/.claude/skills/my-skill"
  mkdir -p "$H/.claude/skills/other" && echo x > "$H/.claude/skills/other/SKILL.md"
  cap
  [ "$status" -eq 0 ]
  [ ! -e "$R/config/claude/skills/my-skill" ]
  [ -f "$R/config/claude/skills/other/SKILL.md" ]
  [ "$(cat "$R/config/claude/CLAUDE.md")" = "repo rules" ]
}

@test "backups and agent-push.sh in ~/.claude/hooks are not captured" {
  mkdir -p "$H/.claude/hooks"
  printf '#!/bin/sh\n' > "$H/.claude/hooks/agent-push.sh"
  printf '#!/bin/sh\n' > "$H/.claude/hooks/agent-push.sh.bak.20261016-190926"
  printf '#!/bin/sh\necho mine\n' > "$H/.claude/hooks/mine.sh"
  cap
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(ls "$R/config/claude/hooks")" = mine.sh ]
}

@test "the global profile and non-empty project memories are captured and mirrored" {
  P="$H/.claude/projects"
  mkdir -p "$H/.claude/profile" "$P/-Users-x-Documents-a/memory" "$P/-Users-x-Documents-b/memory" "$P/-Users-x-Documents-c"
  echo '# me' > "$H/.claude/profile/me.md"
  printf -- '- [A](a.md) — a\n' > "$P/-Users-x-Documents-a/memory/MEMORY.md"
  echo 'fact' > "$P/-Users-x-Documents-a/memory/a.md"
  echo 'transcript' > "$P/-Users-x-Documents-c/session.jsonl"
  cap
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$R/config/claude/profile/me.md")" = '# me' ]
  [ "$(cat "$R/config/claude/memory/-Users-x-Documents-a/a.md")" = fact ]
  # empty memory dirs and session transcripts are not captured
  [ "$(ls "$R/config/claude/memory")" = -Users-x-Documents-a ]
  ! grep -rq transcript "$R/config"
  # a memory deleted on the Mac disappears from the repo on the next capture
  rm "$P/-Users-x-Documents-a/memory/a.md"
  cap
  [ "$status" -eq 0 ]
  [ ! -e "$R/config/claude/memory/-Users-x-Documents-a/a.md" ]
  [ -f "$R/config/claude/memory/-Users-x-Documents-a/MEMORY.md" ]
}
