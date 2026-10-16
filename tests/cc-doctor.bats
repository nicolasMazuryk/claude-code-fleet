#!/usr/bin/env bats
# cc-doctor.bats — per-host health check against a scratch $HOME: fake systemctl/loginctl/launchctl/claude, a private
# tmux socket, no ssh (CC_DOCTOR_CLOUD="").

setup() {
  command -v tmux >/dev/null || skip "tmux not installed"
  REPO=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  export HOME="$BATS_TEST_TMPDIR/home" TMUX_TMPDIR="$BATS_TEST_TMPDIR/tmux" FAKE_SYSTEMD="$BATS_TEST_TMPDIR/systemd"
  export CC_ORCH_CONFIG="$BATS_TEST_TMPDIR/config" NVM_DIR="$BATS_TEST_TMPDIR/no-nvm" CC_DOCTOR_CLOUD=""
  unset TMUX
  B="$HOME/.local/bin"; ROOT="$HOME/root"
  mkdir -p "$B" "$ROOT" "$TMUX_TMPDIR" "$HOME/.claude/hooks" "$HOME/.config/agent-push"
  cp "$REPO/hooks/agent-push.sh" "$HOME/.claude/hooks/"
  printf 'SECRET-TOPIC-123\n' > "$HOME/.config/agent-push/topic"; chmod 600 "$HOME/.config/agent-push/topic"
  for t in claude node gh mosh; do printf '#!/bin/sh\necho "2.1.0 (fake)"\n' > "$B/$t"; chmod +x "$B/$t"; done
  for r in a b c; do git init -q "$ROOT/$r"; done
  printf 'a\nb\n' > "$BATS_TEST_TMPDIR/repos.txt"
}

teardown() { tmux kill-server 2>/dev/null || true; }

link_bins() { # link_bins <skip list>
  for f in "$REPO"/bin/*; do n=${f##*/}; case " README.md $1 " in *" $n "*) ;; *) ln -s "$f" "$B/$n" ;; esac; done
}

cloud_home() {
  link_bins "$(sed -n 's/^ *BIN_SKIP="\([^"]*\)".*/\1/p' "$REPO/install.sh")"
  cp "$REPO/tests/fakes/systemctl" "$REPO/tests/fakes/loginctl" "$B/"
  printf 'AGENT_HOST=cloud\nAGENTS_ROOT=%s\nAGENTS_SESSION=fleet\nCC_ORCH_DIR=%s\nREPOS_FILE=%s\n' \
    "$ROOT" "$REPO" "$BATS_TEST_TMPDIR/repos.txt" > "$CC_ORCH_CONFIG"
  mkdir -p "$FAKE_SYSTEMD/active"; touch "$FAKE_SYSTEMD/linger" "$FAKE_SYSTEMD/active/cc-agents.service" \
    "$FAKE_SYSTEMD/active/cc-rc@a.service"
  printf '{"projects":{"%s":{"hasTrustDialogAccepted":true}}}' "$ROOT/a" > "$HOME/.claude.json"
  h='{"type":"command","command":"~/.local/bin/cc-relay-hook Stop 0 0 abc"}'
  printf '{"hooks":{"Stop":[{"hooks":[%s,%s]}],"Notification":[{"hooks":[%s,%s]}]},"permissions":{"defaultMode":"auto"},"env":{"CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX":"cloud"}}' \
    "$h" "$h" "$h" "$h" > "$HOME/.claude/settings.json"
  tmux new-session -d -s fleet 'sleep 600'
}

mac_home() {
  link_bins ""
  printf '#!/bin/sh\necho "\tstate = running"; echo "\tlast exit code = 0"\n' > "$B/launchctl"
  printf '#!/bin/sh\necho "firewall       ok mosh-server /x/mosh-server allowed"\n' > "$BATS_TEST_TMPDIR/mra"
  chmod +x "$B/launchctl" "$BATS_TEST_TMPDIR/mra"
  printf 'AGENT_HOST=mac\nAGENTS_ROOT=%s\nAGENTS_SESSION=agents\nCC_ORCH_DIR=%s\nREPOS_FILE=%s\n' \
    "$ROOT" "$REPO" "$BATS_TEST_TMPDIR/repos.txt" > "$CC_ORCH_CONFIG"
  export CC_DOCTOR_LIBEXEC="$BATS_TEST_TMPDIR/libexec" CC_DOCTOR_RELAY_LOG="$BATS_TEST_TMPDIR/relay.log" \
    CC_DOCTOR_START_LOG="$BATS_TEST_TMPDIR/start.log" CC_DOCTOR_LA_DIR="$BATS_TEST_TMPDIR/la" CC_DOCTOR_MRA="$BATS_TEST_TMPDIR/mra"
  mkdir -p "$CC_DOCTOR_LIBEXEC" "$CC_DOCTOR_LA_DIR"
  cp "$REPO/bin/agent-relay" "$REPO/bin/agent-present" "$CC_DOCTOR_LIBEXEC/"
  echo '2026-10-17 00:00:00 agent-relay: connected to cloud, waiting for events' > "$CC_DOCTOR_RELAY_LOG"
  p='{"type":"command","command":"afplay x.mp3"}'; q='{"type":"command","command":"~/.claude/hooks/agent-push.sh"}'
  printf '{"remoteControlAtStartup":true,"inputNeededNotifEnabled":false,"agentPushNotifEnabled":false,"env":{"CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX":"mac"},"hooks":{"Stop":[{"hooks":[%s,%s]},{"hooks":[%s]}],"Notification":[{"hooks":[%s,%s]},{"hooks":[%s]}]}}' \
    "$p" "$p" "$q" "$p" "$p" "$q" > "$HOME/.claude/settings.json"
  tmux new-session -d -s agents 'sleep 600'
  tmux new-session -d -s rc -n idle 'sleep 600'
  for r in a b; do tmux new-window -d -t '=rc:' -n "$r" 'sleep 600'; done
}

@test "cloud: healthy host is green, untrusted repo is skipped, the topic is never printed" {
  cloud_home
  run "$B/cc-doctor"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"cloud  ok   rc        cc-rc@a active"* ]]
  [[ "$output" == *"cloud  skip rc        b: workspace not trusted"* ]]
  [[ "$output" == *"warn relay"* ]]                       # no Mac relay attached in the test
  [[ "$output" == *"0 FAIL"* ]]
  [[ "$output" != *SECRET-TOPIC* ]]
}

@test "cloud: a trusted repo without its server, an unlisted server, a legacy unit and a loose topic all FAIL" {
  cloud_home
  rm "$FAKE_SYSTEMD/active/cc-rc@a.service"
  touch "$FAKE_SYSTEMD/active/cc-rc@c.service" "$FAKE_SYSTEMD/active/agent@a.service"
  chmod 644 "$HOME/.config/agent-push/topic"
  run "$B/cc-doctor"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL rc        cc-rc@a not active"* ]]
  [[ "$output" == *"FAIL rc        cc-rc@ running for unlisted or untrusted: c"* ]]
  [[ "$output" == *"FAIL runtime   legacy oci units still present: agent@a.service"* ]]
  [[ "$output" == *"FAIL ntfy      topic mode 644"* ]]
  [[ "$output" != *SECRET-TOPIC* ]]
}

@test "cloud: settings without the 4 relay stand-ins FAIL; an unlinked script FAILs" {
  cloud_home
  echo '{"permissions":{"defaultMode":"auto"}}' > "$HOME/.claude/settings.json"
  rm "$B/rc-servers"
  run "$B/cc-doctor"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL settings  ~/.claude/settings.json: got '0 auto null'"* ]]
  [[ "$output" == *"not linked to $REPO/bin: rc-servers"* ]]
}

@test "mac: healthy host is green" {
  mac_home
  run "$B/cc-doctor"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"mac    ok   rc        tmux rc windows = repos.txt: a b"* ]]
  [[ "$output" == *"ok   tcc       tmux server reads $ROOT"* ]]
  [[ "$output" == *"mac-remote-access: mosh-server /x/mosh-server allowed"* ]]
}

@test "mac: rc drift, stale relay copy, lost relay and fresh TCC denial FAIL" {
  mac_home
  printf 'a\nc\n' > "$BATS_TEST_TMPDIR/repos.txt"          # c listed, no window; b has a window, unlisted
  echo changed > "$CC_DOCTOR_LIBEXEC/agent-relay"
  echo '2026-10-17 00:01:00 agent-relay: connection to cloud ended; retrying in 5s' >> "$CC_DOCTOR_RELAY_LOG"
  touch -t 202601010000 "$CC_DOCTOR_LA_DIR/cc-orchestrator.claude.agents.plist"
  echo 'bash: x: Operation not permitted' > "$CC_DOCTOR_START_LOG"
  run "$B/cc-doctor"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL rc        tmux rc missing: c unlisted: b"* ]]
  [[ "$output" == *"FAIL relay     stale copies"*"agent-relay"* ]]
  [[ "$output" == *"FAIL relay     connection to cloud ended"* ]]
  [[ "$output" == *"FAIL tcc"*"Operation not permitted"* ]]
}
