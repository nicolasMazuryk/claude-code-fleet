#!/usr/bin/env bats
# egress.bats — the egress gateway (config/cloud/egress): compose validity, the G2 nftables ruleset (exact sets, skuid
# match), the gost bypass + limiter, the daily-bytes alert threshold path, Mac→cloud secret delivery, install step.

setup() {
  REPO="$BATS_TEST_DIRNAME/.."
  E="$REPO/config/cloud/egress"
  export DOCKER_CONFIG="${DOCKER_CONFIG:-$HOME/.docker}"   # the compose plugin lives under the real HOME
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
}

# the nftables rule lines of the output chain, whitespace-normalised
rules() { grep -E '^[[:space:]]*meta skuid' "$E/guard.nft" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+/ /g'; }

@test "compose.yaml is valid and publishes gost on host 8443 from the tailscale namespace" {
  command -v docker >/dev/null || skip "docker not installed"
  export EGRESS_STATE_DIR=/tmp/s EGRESS_SECRETS_DIR=/tmp/x
  run docker compose -f "$E/compose.yaml" config --format json
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.services.tailscale.ports | map(select(.published == "8443" and .target == 8443)) | length == 1' <<<"$output"
  jq -e '.services.gost.network_mode == "service:tailscale" and .services.guard.network_mode == "service:tailscale"' <<<"$output"
  jq -e '.services.gost.depends_on.guard.condition == "service_healthy"' <<<"$output"
  jq -e '.services.tailscale.environment.TS_EXTRA_ARGS | test("tag:egress")' <<<"$output"
}

@test "gost runs as the uid the nftables rules match" {
  uid=$(grep -oE 'user: "[0-9]+' "$E/compose.yaml" | grep -oE '[0-9]+')
  [ "$uid" = 10001 ]
  [ "$(rules | grep -c "meta skuid $uid ")" -eq 5 ]
  [ "$(rules | wc -l | tr -d ' ')" -eq 5 ]
}

@test "guard.nft carries the G2 ruleset: exact sets, skuid match, drop" {
  r=$(rules)
  grep -qxF 'meta skuid 10001 ip daddr { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 198.18.0.0/15, 224.0.0.0/3 } drop' <<<"$r"
  grep -qxF 'meta skuid 10001 ip6 daddr { ::1, fc00::/7, fe80::/10, ::ffff:0:0/96 } drop' <<<"$r"
  grep -qxF 'meta skuid 10001 tcp dport != { 80, 443 } drop' <<<"$r"
  grep -qxF 'meta skuid 10001 counter name "egress_bytes"' <<<"$r"
  grep -qxF 'meta skuid 10001 ct direction reply counter name "egress_bytes" accept' <<<"$r"
  # tailscaled's own traffic is never matched: every rule in the output filter chain names the skuid
  [ "$(awk '/chain output \{/{f=1;next} f&&/^\t\}/{f=0} f&&/^\t\t[a-z]/&&!/^\t\ttype /' "$E/guard.nft" | grep -vc 'meta skuid 10001')" -eq 0 ]
}

@test "guard.nft: replies to inbound connections are accepted before the drops; the open-connection counter follows them" {
  awk '/ct direction reply .*accept$/{a=NR} /drop$/{if(!d)d=NR; l=NR} /skuid 10001 counter name/{c=NR} END{exit !(a && d && a < d && l < c)}' "$E/guard.nft"
}

@test "guard.nft: the reply-routing marks are in place" {
  grep -q 'iifname "eth0" tcp dport 8443 ct mark set ct mark | 0x2' "$E/guard.nft"
  grep -q 'ct mark & 0x2 == 0x2 meta mark set meta mark | 0x2' "$E/guard.nft"
  grep -q "fwmark 0x2/0x2 lookup main priority 5100" "$E/guard.sh"
}

@test "gost.yaml: bypass denies the private ranges and ports other than 80/443; limiter set; upstream slot disabled" {
  for c in 169.254.0.0/16 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 127.0.0.0/8; do
    grep -qE "^  - $c\$" "$E/gost.yaml" || { echo "missing $c"; return 1; }
  done
  grep -qF "'*:0-79'" "$E/gost.yaml" && grep -qF "'*:81-442'" "$E/gost.yaml" && grep -qF "'*:444-65535'" "$E/gost.yaml"
  grep -qE '^  bypass: deny-private' "$E/gost.yaml"
  grep -qE '^  limiter: egress-rate' "$E/gost.yaml"
  grep -qE "^  - '\\$ [0-9]+MB [0-9]+MB'" "$E/gost.yaml"
  grep -qE '^    # chain: upstream' "$E/gost.yaml"        # -F slot wired but disabled
  grep -qE '^    type: tls' "$E/gost.yaml"
  ! grep -qiE 'password: ' "$E/gost.yaml"                 # credentials come from the auther file, never the config
}

# --- egress-bytes-alert ---------------------------------------------------------------------------------------------
alert_setup() {
  export EGRESS_STATE="$BATS_TEST_TMPDIR/bytes.state" EGRESS_DAILY_BYTES=1000 EGRESS_DAY=2026-10-22
  export AGENT_PUSH_HOOK="$BATS_TEST_TMPDIR/hook" PUSHES="$BATS_TEST_TMPDIR/pushes"
  printf '#!/bin/sh\ncat >> "$PUSHES"\n' > "$AGENT_PUSH_HOOK"; chmod +x "$AGENT_PUSH_HOOK"
  : > "$PUSHES"
}
alert() { EGRESS_COUNTER_CMD="echo $1" "$REPO/bin/egress-bytes-alert"; }

@test "egress-bytes-alert: silent below the threshold, one push past it, no repeat the same day" {
  alert_setup
  run alert 100; [ "$status" -eq 0 ]; [ ! -s "$PUSHES" ]       # first reading is the day's baseline
  run alert 900; [ "$status" -eq 0 ]; [ ! -s "$PUSHES" ]       # 800 sent today
  run alert 1300; [ "$status" -eq 0 ]; [[ "$output" == *ALERT* ]]
  [ "$(jq -r .hook_event_name "$PUSHES")" = Notification ] && [ "$(jq -r .notification_type "$PUSHES")" = agent_needs_input ]
  run alert 5000; [ "$(jq -s length "$PUSHES")" -eq 1 ]
}

@test "egress-bytes-alert: a counter reset (guard restart) adds the new value; a new day starts from zero" {
  alert_setup
  alert 100 >/dev/null; alert 900 >/dev/null
  run alert 300; [[ "$output" == *ALERT* ]] && [ -s "$PUSHES" ]   # reset: 800 + 300 = 1100 > 1000
  export EGRESS_DAY=2026-10-23
  : > "$PUSHES"; run alert 400; [ ! -s "$PUSHES" ]
  [ "$(cut -d' ' -f3,4 "$EGRESS_STATE")" = "0 0" ]
}

@test "egress-bytes-alert fails on an unreadable counter" {
  alert_setup
  EGRESS_COUNTER_CMD="echo notanumber" run "$REPO/bin/egress-bytes-alert"
  [ "$status" -eq 1 ]
}

# --- egress-secrets-push --------------------------------------------------------------------------------------------
push_setup() {
  export PATH="$REPO/tests/fakes/egress:$PATH" FAKE_KEYCHAIN="$BATS_TEST_TMPDIR/kc"
  mkdir -p "$FAKE_KEYCHAIN" "$HOME"
  printf 's3cret-pw' > "$FAKE_KEYCHAIN/cc-egress-proxy-password"
}

@test "egress-secrets-push delivers 'user password' over stdin, 0400, never in output, then changes nothing" {
  push_setup
  run "$REPO/bin/egress-secrets-push"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" != *s3cret-pw* ]]
  [ "$(cat "$HOME/.config/egress/gost-auth")" = "browseruse s3cret-pw" ]
  [ "$(stat -f %Lp "$HOME/.config/egress/gost-auth" 2>/dev/null || stat -c %a "$HOME/.config/egress/gost-auth")" = 400 ]
  [[ "$output" == *"WARNING: no Keychain item cc-egress-ts-authkey"* ]]
  run "$REPO/bin/egress-secrets-push"
  [[ "$output" == *"ok cloud:~/.config/egress/gost-auth"* ]] && [[ "$output" != *"delivered gost-auth"* ]]
}

@test "egress-secrets-push --dry-run writes nothing; a missing Keychain item only warns" {
  push_setup
  run "$REPO/bin/egress-secrets-push" --dry-run
  [[ "$output" == *"would deliver gost-auth"* ]]; [ ! -e "$HOME/.config/egress/gost-auth" ]
  rm "$FAKE_KEYCHAIN/cc-egress-proxy-password"
  run "$REPO/bin/egress-secrets-push"
  [ "$status" -eq 0 ]; [[ "$output" == *"WARNING: no Keychain item cc-egress-proxy-password"* ]]
}

@test "the proxy password is never read from Vault by any egress file" {
  ! grep -rnE 'core-secret-egress-proxy-password|vault_get' "$E" "$REPO/bin/egress-secrets-push" "$REPO/bin/egress-bytes-alert"
}

# --- browser-router env file (J11) ------------------------------------------------------------------------------------
env_setup() {
  push_setup
  printf 'bu-key-123' > "$FAKE_KEYCHAIN/cc-browser-use-api-key"
  printf '203.0.113.7' > "$FAKE_KEYCHAIN/cc-egress-public-host"
  F="$HOME/.config/browser-router/env"
  mode() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
}

@test "egress-secrets-push writes the cloud env file 0600 with all keys, then changes nothing" {
  env_setup
  run "$REPO/bin/egress-secrets-push"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(mode "$F")" = 600 ]
  [ "$(sort "$F")" = "$(printf '%s\n' BROWSER_ROUTER_EGRESS_HOST=203.0.113.7 BROWSER_ROUTER_EGRESS_PASSWORD=s3cret-pw BROWSER_ROUTER_EGRESS_PORT=8443 BROWSER_ROUTER_EGRESS_USER=browseruse BROWSER_USE_API_KEY=bu-key-123 | sort)" ]
  for v in bu-key-123 s3cret-pw 203.0.113.7; do [[ "$output" != *"$v"* ]]; done
  run "$REPO/bin/egress-secrets-push"
  [[ "$output" == *"ok cloud browser-router env"* ]] && [[ "$output" != *"wrote cloud"* ]]
}

@test "egress-secrets-push --local writes the Mac env file 0600; --dry-run writes nothing" {
  env_setup
  run "$REPO/bin/egress-secrets-push" --local --dry-run
  [[ "$output" == *"would write the local"* ]]; [ ! -e "$F" ]
  run "$REPO/bin/egress-secrets-push" --local
  [ "$status" -eq 0 ]; [ "$(mode "$F")" = 600 ]
  grep -qx 'BROWSER_USE_API_KEY=bu-key-123' "$F"
  [ ! -e "$HOME/.config/egress/gost-auth" ]
  [[ "$output" != *bu-key-123* ]]
}

@test "env file: a missing Keychain item skips its key with a log line; no item at all writes no file" {
  env_setup
  rm "$FAKE_KEYCHAIN/cc-egress-public-host"
  run "$REPO/bin/egress-secrets-push" --local
  [ "$status" -eq 0 ]; [[ "$output" == *"skip BROWSER_ROUTER_EGRESS_HOST"* ]]
  ! grep -q EGRESS_HOST "$F"; grep -q EGRESS_PASSWORD "$F"
  rm -f "$F" "$FAKE_KEYCHAIN"/*
  run "$REPO/bin/egress-secrets-push" --local
  [ "$status" -eq 0 ]; [ ! -e "$F" ]
}

@test "env file: no secret value appears on any argv (ssh/security/shasum calls)" {
  env_setup
  cat > "$BATS_TEST_TMPDIR/ssh-spy" <<SPY
#!/bin/bash
echo "\$*" >> "$BATS_TEST_TMPDIR/argv"
exec "$REPO/tests/fakes/egress/ssh" "\$@"
SPY
  chmod +x "$BATS_TEST_TMPDIR/ssh-spy"; mkdir -p "$BATS_TEST_TMPDIR/spy"; cp "$BATS_TEST_TMPDIR/ssh-spy" "$BATS_TEST_TMPDIR/spy/ssh"
  PATH="$BATS_TEST_TMPDIR/spy:$PATH" run "$REPO/bin/egress-secrets-push"
  [ "$status" -eq 0 ]; [ -s "$BATS_TEST_TMPDIR/argv" ]
  ! grep -E 'bu-key-123|s3cret-pw|203\.0\.113\.7' "$BATS_TEST_TMPDIR/argv"
}
