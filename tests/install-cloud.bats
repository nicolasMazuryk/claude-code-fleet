#!/usr/bin/env bats
# install-cloud.bats — cloud side, run on the Mac against a scratch HOME with fake systemctl/loginctl (no sudo):
# rc-servers' cloud reconcile (trust gate, legacy agent@ stop, unlisted cc-rc@ disabled) and
# ./install.sh cloud-local (legacy removal, units, idempotence, dry run).

setup() {
  REPO="$BATS_TEST_DIRNAME/.."
  export HOME="$BATS_TEST_TMPDIR/home" FAKE_SYSTEMD="$BATS_TEST_TMPDIR/systemd"
  export PATH="$BATS_TEST_DIRNAME/fakes:$PATH" CC_SUDO="" NVM_DIR="$BATS_TEST_TMPDIR/no-nvm"
  mkdir -p "$HOME/.local/bin" "$FAKE_SYSTEMD/active" "$FAKE_SYSTEMD/enabled" "$BATS_TEST_TMPDIR/fleet"
  ROOT="$BATS_TEST_TMPDIR/fleet"
}

trust() { # trust <dir>…: mark workspaces trusted in ~/.claude.json
  local j='{"projects":{}}' d
  for d in "$@"; do j=$(jq --arg d "$d" '.projects[$d] = {hasTrustDialogAccepted: true}' <<<"$j"); done
  printf '%s\n' "$j" > "$HOME/.claude.json"
}

rc_setup() {
  for s in agent-env rc-servers; do ln -sf "$REPO/bin/$s" "$HOME/.local/bin/$s"; done
  export CC_ORCH_CONFIG="$BATS_TEST_TMPDIR/config"
  printf 'AGENT_HOST=cloud\nAGENTS_ROOT=%s\nREPOS_FILE=%s\n' "$ROOT" "$BATS_TEST_TMPDIR/repos.txt" > "$CC_ORCH_CONFIG"
  for r in a b c; do git init -q "$ROOT/$r"; done
  printf 'a\nb\nc\nnotcloned\n' > "$BATS_TEST_TMPDIR/repos.txt"
}

@test "rc-servers (cloud) starts trusted listed repos only, stopping a legacy agent@ first" {
  rc_setup; trust "$ROOT/a" "$ROOT/b"
  touch "$FAKE_SYSTEMD/active/agent@a.service" "$FAKE_SYSTEMD/enabled/agent@a.service"
  run "$HOME/.local/bin/rc-servers"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"stopped legacy agent@a"* ]]
  [[ "$output" == *"started cc-rc@a"* && "$output" == *"started cc-rc@b"* ]]
  [[ "$output" == *"skip c: workspace not trusted"* && "$output" == *"skip notcloned: not cloned"* ]]
  [ ! -e "$FAKE_SYSTEMD/active/agent@a.service" ] && [ ! -e "$FAKE_SYSTEMD/enabled/agent@a.service" ]
  [ -e "$FAKE_SYSTEMD/active/cc-rc@a.service" ] && [ -e "$FAKE_SYSTEMD/enabled/cc-rc@b.service" ]
  [ ! -e "$FAKE_SYSTEMD/active/cc-rc@c.service" ]
  # agent@a stopped before cc-rc@a started
  [ "$(grep -n 'agent@a' "$FAKE_SYSTEMD/calls" | grep disable | cut -d: -f1)" -lt "$(grep -n 'enable --now cc-rc@a' "$FAKE_SYSTEMD/calls" | cut -d: -f1)" ]
}

@test "rc-servers (cloud) is idempotent and disables repos dropped from the list" {
  rc_setup; trust "$ROOT/a" "$ROOT/b"
  "$HOME/.local/bin/rc-servers" >/dev/null 2>&1
  run "$HOME/.local/bin/rc-servers"
  [[ "$output" != *started* && "$output" != *stopped* ]]
  printf 'b\n' > "$BATS_TEST_TMPDIR/repos.txt"
  run "$HOME/.local/bin/rc-servers"
  [[ "$output" == *"stopped cc-rc@a"* ]]
  [ ! -e "$FAKE_SYSTEMD/enabled/cc-rc@a.service" ] && [ -e "$FAKE_SYSTEMD/active/cc-rc@b.service" ]
}

local_setup() {
  export CC_INSTALL_ANY_OS=1 CC_INSTALL_NO_CLAUDE=1 CC_INSTALL_NO_CLONE=1 CC_AGENTS_ROOT="$ROOT"
  export CC_UNIT_DIR="$BATS_TEST_TMPDIR/units" CC_RSYSLOG_DIR="$BATS_TEST_TMPDIR/rsyslog.d"
  export CC_LOG_DIR="$BATS_TEST_TMPDIR/log" CC_LEGACY_BIN="$BATS_TEST_TMPDIR/usr-local-bin-fleet"
  export CC_TMUX_DIR="$BATS_TEST_TMPDIR/tmux"
  unset CC_ORCH_CONFIG
  mkdir -p "$CC_UNIT_DIR" "$CC_RSYSLOG_DIR" "$CC_TMUX_DIR"
  printf '# Ubuntu .bashrc\ncase $- in *i*) ;; *) return;; esac\n' > "$HOME/.bashrc"
  # what oci left behind: the legacy unit file + an enabled, running instance, and the fleet CLI
  printf '[Unit]\n' > "$CC_UNIT_DIR/agent@.service"
  touch "$FAKE_SYSTEMD/active/agent@offers-pipeline.service" "$FAKE_SYSTEMD/enabled/agent@offers-pipeline.service"
  printf '#!/bin/sh\n' > "$CC_LEGACY_BIN"
}

@test "cloud-local: removes the legacy setup, installs units/config/links and starts cc-agents" {
  local_setup
  run "$REPO/install.sh" cloud-local
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ ! -e "$CC_UNIT_DIR/agent@.service" ] && [ ! -e "$CC_LEGACY_BIN" ]
  [ ! -e "$FAKE_SYSTEMD/active/agent@offers-pipeline.service" ] && [ ! -e "$FAKE_SYSTEMD/enabled/agent@offers-pipeline.service" ]
  cmp "$REPO/config/cloud/systemd/cc-rc@.service" "$CC_UNIT_DIR/cc-rc@.service"
  cmp "$REPO/config/cloud/systemd/cc-agents.service" "$CC_UNIT_DIR/cc-agents.service"
  cmp "$REPO/config/cloud/rsyslog-cc-orchestrator.conf" "$CC_RSYSLOG_DIR/30-cc-orchestrator.conf"
  [ -e "$CC_LOG_DIR/agent.log" ]
  [ -e "$FAKE_SYSTEMD/active/cc-agents.service" ] && [ -e "$FAKE_SYSTEMD/enabled/cc-agents.service" ]
  [ -e "$FAKE_SYSTEMD/linger" ]
  grep -qx 'AGENT_HOST=cloud' "$HOME/.config/cc-orchestrator/config"
  grep -q "CC_ORCH_DIR=\"$(cd "$REPO" && pwd)\"" "$HOME/.config/cc-orchestrator/config"
  [ "$(readlink "$HOME/.local/bin/rc-serve")" = "$(cd "$REPO" && pwd)/bin/rc-serve" ]
  [ -L "$HOME/.local/bin/cc-relay-hook" ]
  cmp "$REPO/config/mac/tmux.conf" "$HOME/.tmux.conf"
  # PATH line goes first, before Ubuntu's non-interactive return; the old content is kept and backed up
  head -n1 "$HOME/.bashrc" | grep -q 'cc-orchestrator: ~/.local/bin on PATH'
  grep -q 'Ubuntu .bashrc' "$HOME/.bashrc"
  ls "$HOME"/.bashrc.bak.* >/dev/null
  # ac/am shortcuts: sourced at the end (interactive shells only); ac attaches the local fleet session
  tail -n1 "$HOME/.bashrc" | grep -q 'bashrc.snippet'
  [ -L "$HOME/.config/cc-orchestrator/bashrc.snippet" ]
  run bash -c $'shopt -s expand_aliases\n. "$HOME/.config/cc-orchestrator/bashrc.snippet"\nalias ac\nam'
  [[ "$output" == *"tmux -u new -A -s fleet ~/.local/bin/agents-loop"* ]] && [[ "$output" == *"never connects to the Mac"* ]] && [ "$status" -ne 0 ]
}

@test "cloud-local: second run changes nothing" {
  local_setup
  "$REPO/install.sh" cloud-local >/dev/null
  before=$(find "$HOME" -name '*.bak.*' | wc -l)
  run "$REPO/install.sh" cloud-local
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"install.sh cloud-local: no changes"* ]] || { echo "$output"; return 1; }
  [ "$(find "$HOME" -name '*.bak.*' | wc -l)" -eq "$before" ]
  [ "$(grep -c 'cc-orchestrator: ~/.local/bin on PATH' "$HOME/.bashrc")" -eq 1 ]
}

@test "cloud-local --dry-run (CC_DRY_RUN=1) reports and writes nothing" {
  local_setup
  snap() { find "$HOME" "$CC_UNIT_DIR" "$CC_RSYSLOG_DIR" "$FAKE_SYSTEMD" -not -name calls | sort; cat "$HOME/.bashrc"; }
  a=$(snap)
  run env CC_DRY_RUN=1 "$REPO/install.sh" cloud-local
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"would stop + disable agent@offers-pipeline.service"* ]]
  [[ "$output" == *"would install $CC_UNIT_DIR/cc-rc@.service"* ]]
  [[ "$output" == *"change(s) would be made"* ]]
  [ "$(snap)" = "$a" ]
  ! grep -qE ' (enable|disable|restart)' "$FAKE_SYSTEMD/calls" 2>/dev/null
}

@test "cloud-local-rollback restores the legacy agent@ setup kept by the install, then re-install works" {
  local_setup
  export CC_LEGACY_BAK="$BATS_TEST_TMPDIR/legacy-bak"
  "$REPO/install.sh" cloud-local >/dev/null
  touch "$FAKE_SYSTEMD/active/cc-rc@offers-pipeline.service" "$FAKE_SYSTEMD/enabled/cc-rc@offers-pipeline.service"
  run "$REPO/install.sh" cloud-local-rollback
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ ! -e "$FAKE_SYSTEMD/active/cc-rc@offers-pipeline.service" ] && [ ! -e "$FAKE_SYSTEMD/active/cc-agents.service" ]
  [ ! -e "$CC_UNIT_DIR/cc-rc@.service" ] && [ ! -e "$CC_RSYSLOG_DIR/30-cc-orchestrator.conf" ]
  [ -e "$CC_UNIT_DIR/agent@.service" ] && [ -x "$CC_LEGACY_BIN" ]
  [ -e "$FAKE_SYSTEMD/active/agent@offers-pipeline.service" ] && [ -e "$FAKE_SYSTEMD/enabled/agent@offers-pipeline.service" ]
  # and forward again
  run "$REPO/install.sh" cloud-local
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_SYSTEMD/active/agent@offers-pipeline.service" ] && [ -e "$CC_UNIT_DIR/cc-rc@.service" ]
  [ "$(grep -c . "$CC_LEGACY_BAK/units")" -eq 1 ]
}

@test "cloud-local-rollback refuses without a legacy backup" {
  local_setup
  export CC_LEGACY_BAK="$BATS_TEST_TMPDIR/none"
  run "$REPO/install.sh" cloud-local-rollback
  [ "$status" -ne 0 ]
  [[ "$output" == *"no legacy backup"* ]]
}

# browser-router on cloud: fake corepack/npm stand in for the build and the agent-browser install
browser_fakes() {
  local b="$BATS_TEST_TMPDIR/fakebin"; mkdir -p "$b"
  printf '#!/bin/sh\ncase "$*" in *build*) mkdir -p dist; printf "#!/bin/sh\\n" > dist/cli.js; chmod +x dist/cli.js ;; esac\n' > "$b/corepack"
  # shellcheck disable=SC2016
  printf '#!/bin/sh\nprintf "#!/bin/sh\\n[ \\"\\$1\\" = --version ] && echo \\"agent-browser 0.39.1\\"\\nexit 0\\n" > "$HOME/.local/bin/agent-browser"; chmod +x "$HOME/.local/bin/agent-browser"\necho "$*" >> "$HOME/npm.calls"\n' > "$b/npm"
  chmod +x "$b/corepack" "$b/npm"
  export PATH="$b:$HOME/.local/bin:$PATH"
  export CC_BROWSER_DIR="$BATS_TEST_TMPDIR/browser-router"
  git init -q "$CC_BROWSER_DIR"
  git -C "$CC_BROWSER_DIR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
}

@test "cloud-local: vault drain units are installed; the timer stays off until browser-router exists" {
  local_setup
  export CC_INSTALL_NO_BROWSER=1
  run "$REPO/install.sh" cloud-local
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  cmp "$REPO/config/cloud/systemd/browser-router-vault-drain.service" "$CC_UNIT_DIR/browser-router-vault-drain.service"
  cmp "$REPO/config/cloud/systemd/browser-router-vault-drain.timer" "$CC_UNIT_DIR/browser-router-vault-drain.timer"
  [ -z "$(ls "$FAKE_SYSTEMD/enabled" | grep vault-drain || true)" ]
  # cloud links the cloud-side scripts, not the Mac-only ones
  [ -L "$HOME/.local/bin/browser-relay-cloud" ] && [ -L "$HOME/.local/bin/browser-vault-drain" ]
  [ ! -e "$HOME/.local/bin/browser-up" ] && [ ! -e "$HOME/.local/bin/browser-relay-handler" ]
}

@test "cloud-local: browser-router is built and linked, agent-browser pinned, drain timer enabled; rerun changes nothing" {
  local_setup; browser_fakes
  run "$REPO/install.sh" cloud-local
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -x "$CC_BROWSER_DIR/dist/cli.js" ]
  [ "$(readlink "$HOME/.local/bin/browser-router")" = "$CC_BROWSER_DIR/dist/cli.js" ]
  grep -qx 'install -g agent-browser@0.39.1' "$HOME/npm.calls"
  [ -e "$FAKE_SYSTEMD/enabled/browser-router-vault-drain.timer.service" ]
  run "$REPO/install.sh" cloud-local
  [[ "$output" == *"no changes"* ]] || { echo "$output"; return 1; }
  [ "$(wc -l < "$HOME/npm.calls")" -eq 1 ]
}

@test "cloud-local --dry-run with browser-router missing writes nothing for it" {
  local_setup
  export CC_INSTALL_NO_CLONE=0 CC_DRY_RUN=1 CC_BROWSER_DIR="$BATS_TEST_TMPDIR/absent"
  run "$REPO/install.sh" cloud-local
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"would clone"*browser-router* ]]
  [ ! -e "$CC_BROWSER_DIR" ]
}

@test "cloud-local: egress units installed, stack stays off until the Mac delivers gost-auth, then enabled; idempotent" {
  local_setup
  run "$REPO/install.sh" cloud-local
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  for u in cc-egress.service cc-egress-bytes.service cc-egress-bytes.timer; do cmp "$REPO/config/cloud/systemd/$u" "$CC_UNIT_DIR/$u"; done
  [ -d "$HOME/.config/egress" ] && [ -f "$HOME/.config/egress/ts-authkey" ]
  [ "$(stat -f %Lp "$HOME/.config/egress" 2>/dev/null || stat -c %a "$HOME/.config/egress")" = 700 ]
  [[ "$output" == *"gost-auth not delivered"* ]]
  [ ! -e "$FAKE_SYSTEMD/enabled/cc-egress.service" ]
  printf 'browseruse pw\n' > "$HOME/.config/egress/gost-auth"
  run "$REPO/install.sh" cloud-local
  [ -e "$FAKE_SYSTEMD/enabled/cc-egress.service" ] && [ -e "$FAKE_SYSTEMD/enabled/cc-egress-bytes.timer.service" ]  # the fake appends .service
  run "$REPO/install.sh" cloud-local
  [[ "$output" == *"no changes"* ]] || { echo "$output"; return 1; }
}
