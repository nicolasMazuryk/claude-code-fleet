#!/usr/bin/env bats
# browser-vault-drain.bats — host-neutral drain wrapper: finds browser-router without PATH, relay sum on cloud only.
bats_require_minimum_version 1.5.0

setup() {
  REPO="$BATS_TEST_DIRNAME/.."
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/bin" "$HOME/.nvm/versions/node/v20.1.0/bin" "$HOME/.nvm/versions/node/v24.2.0/bin" "$BATS_TEST_TMPDIR/fakebin"
  for v in v20.1.0 v24.2.0; do
    printf '#!/bin/sh\necho "router %s args=$* sum=${BROWSER_ROUTER_RELAY_SUM-unset} cfc=$CLAUDE_CODE_ENABLE_CFC"\n' "$v" \
      > "$HOME/.nvm/versions/node/$v/bin/browser-router"
    chmod +x "$HOME/.nvm/versions/node/$v/bin/browser-router"
  done
  printf '#!/bin/sh\necho SUM123\n' > "$BATS_TEST_TMPDIR/fakebin/browser-relay-cloud"
  chmod +x "$BATS_TEST_TMPDIR/fakebin/browser-relay-cloud"
  # a PATH without browser-router, like launchd's
  export PATH="$BATS_TEST_TMPDIR/fakebin:/usr/bin:/bin"
}

@test "finds the newest nvm browser-router when PATH lacks it and runs vault drain" {
  run "$REPO/bin/browser-vault-drain"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"router v24.2.0 args=vault drain"* ]]
}

@test "BROWSER_ROUTER_BIN wins and extra args pass through" {
  printf '#!/bin/sh\necho "own $*"\n' > "$HOME/bin/br"; chmod +x "$HOME/bin/br"
  BROWSER_ROUTER_BIN="$HOME/bin/br" run "$REPO/bin/browser-vault-drain" --x
  [ "$output" = "own vault drain --x" ]
}

@test "relay sum is exported off the Mac only" {
  run "$REPO/bin/browser-vault-drain"
  if [ "$(uname)" = Darwin ]; then [[ "$output" == *"sum=unset"* ]]; else [[ "$output" == *"sum=SUM123"* ]]; fi
}

@test "exits 127 when browser-router is nowhere" {
  rm -rf "$HOME/.nvm"
  run -127 "$REPO/bin/browser-vault-drain"
  [[ "$output" == *"browser-router not found"* ]]
}
