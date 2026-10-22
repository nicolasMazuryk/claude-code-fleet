#!/usr/bin/env bats
# egress-cert.bats — egress gateway certificate: bin/egress-cert-renew (Mac, lego/security/ssh stubbed), bin/egress-cert-check
# (cloud expiry alert), the gost/compose wiring, the launchd agent and the install step.

setup() {
  REPO="$BATS_TEST_DIRNAME/.."
  E="$REPO/config/cloud/egress"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export PATH="$REPO/tests/fakes/egress:$PATH" FAKE_KEYCHAIN="$BATS_TEST_TMPDIR/kc"
  export FAKE_LEGO_LOG="$BATS_TEST_TMPDIR/lego.log" FAKE_DOCKER_LOG="$BATS_TEST_TMPDIR/docker.log"
  export FAKE_CERT_DIR="$BATS_TEST_TMPDIR/certs" EGRESS_ACME_DIR="$BATS_TEST_TMPDIR/acme"
  export EGRESS_CERT_DOMAIN=egress.example.test EGRESS_ACME_SERVER=letsencrypt-staging EGRESS_LEGO="$REPO/tests/fakes/egress/lego"
  mkdir -p "$FAKE_KEYCHAIN" "$FAKE_CERT_DIR"; : > "$FAKE_LEGO_LOG"; : > "$FAKE_DOCKER_LOG"
  printf 'cf-token-xyz' > "$FAKE_KEYCHAIN/cc-cf-acme-dns-token"
  mkcert egress.example.test 90
  R="$HOME/.config/egress/tls"
  mode() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
}

mkcert() { # mkcert <cn> <days>: self-signed pair into $FAKE_CERT_DIR
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days "$2" -subj "/CN=$1" \
    -keyout "$FAKE_CERT_DIR/key.pem" -out "$FAKE_CERT_DIR/cert.pem" 2>/dev/null
}

# --- egress-cert-renew -----------------------------------------------------------------------------------------------
@test "renew: first run pushes cert 0444 and key 0400, restarts gost, passes the token by env only, no value on argv" {
  mkdir -p "$BATS_TEST_TMPDIR/spy"
  cat > "$BATS_TEST_TMPDIR/spy/ssh" <<SPY
#!/bin/bash
echo "\$*" >> "$BATS_TEST_TMPDIR/argv"
exec "$REPO/tests/fakes/egress/ssh" "\$@"
SPY
  chmod +x "$BATS_TEST_TMPDIR/spy/ssh"
  PATH="$BATS_TEST_TMPDIR/spy:$PATH" run "$REPO/bin/egress-cert-renew"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(mode "$R/key.pem")" = 400 ] && [ "$(mode "$R/cert.pem")" = 444 ]
  cmp "$R/cert.pem" "$FAKE_CERT_DIR/cert.pem" && cmp "$R/key.pem" "$FAKE_CERT_DIR/key.pem"
  grep -q 'docker restart egress-gost-1' "$FAKE_DOCKER_LOG"
  grep -q 'token-env-set' "$FAKE_LEGO_LOG"; ! grep -q 'cf-token-xyz' "$FAKE_LEGO_LOG"
  grep -qE 'run .*--server letsencrypt-staging .*--dns cloudflare .*-d egress.example.test' "$FAKE_LEGO_LOG"
  ! grep -q -- '--renew-days' "$FAKE_LEGO_LOG"                       # ARI / 1/3 lifetime is lego's own decision
  [ "$(mode "$EGRESS_ACME_DIR")" = 700 ]
  [[ "$output" != *cf-token-xyz* ]]
  key_b64=$(grep -v -- '-----' "$FAKE_CERT_DIR/key.pem" | head -1)
  ! grep -qF "$key_b64" "$BATS_TEST_TMPDIR/argv"; ! grep -q 'cf-token-xyz' "$BATS_TEST_TMPDIR/argv"
}

@test "renew: skipped (no push, no restart) when cloud already holds the same certificate" {
  "$REPO/bin/egress-cert-renew" >/dev/null
  : > "$FAKE_DOCKER_LOG"; touch -r "$R/cert.pem" "$BATS_TEST_TMPDIR/stamp"
  run "$REPO/bin/egress-cert-renew"
  [ "$status" -eq 0 ]; [[ "$output" == *"certificate unchanged"* ]]
  [ ! -s "$FAKE_DOCKER_LOG" ]
}

@test "renew: a new certificate from lego is pushed again and gost restarted" {
  "$REPO/bin/egress-cert-renew" >/dev/null
  : > "$FAKE_DOCKER_LOG"; mkcert egress.example.test 80
  run "$REPO/bin/egress-cert-renew"
  [[ "$output" == *"delivered cert.pem and key.pem"* ]]
  cmp "$R/cert.pem" "$FAKE_CERT_DIR/cert.pem"; [ "$(mode "$R/key.pem")" = 400 ]
  grep -q 'docker restart' "$FAKE_DOCKER_LOG"
}

@test "renew: missing Keychain token skips with a log line, never calls lego" {
  rm "$FAKE_KEYCHAIN/cc-cf-acme-dns-token"
  run "$REPO/bin/egress-cert-renew"
  [ "$status" -eq 0 ]; [[ "$output" == *"skip: no Keychain item cc-cf-acme-dns-token"* ]]
  [ ! -s "$FAKE_LEGO_LOG" ]; [ ! -e "$R/cert.pem" ]
}

@test "renew: missing lego binary skips; --dry-run calls no ACME and writes nothing" {
  EGRESS_LEGO=/nonexistent/lego run "$REPO/bin/egress-cert-renew"
  [ "$status" -eq 0 ]; [[ "$output" == *"skip: /nonexistent/lego not installed"* ]]
  run "$REPO/bin/egress-cert-renew" --dry-run
  [ "$status" -eq 0 ]; [ ! -s "$FAKE_LEGO_LOG" ]; [ ! -e "$R/cert.pem" ]
}

@test "renew: a failing lego exits non-zero and pushes nothing" {
  printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/badlego"; chmod +x "$BATS_TEST_TMPDIR/badlego"
  EGRESS_LEGO="$BATS_TEST_TMPDIR/badlego" run "$REPO/bin/egress-cert-renew"
  [ "$status" -eq 1 ]; [ ! -e "$R/cert.pem" ]
}

# --- egress-cert-check -----------------------------------------------------------------------------------------------
check_setup() {
  export EGRESS_CERT_FILE="$FAKE_CERT_DIR/cert.pem" EGRESS_CERT_STATE="$BATS_TEST_TMPDIR/cert.state"
  export AGENT_PUSH_HOOK="$BATS_TEST_TMPDIR/hook" PUSHES="$BATS_TEST_TMPDIR/pushes"
  printf '#!/bin/sh\ncat >> "$PUSHES"\n' > "$AGENT_PUSH_HOOK"; chmod +x "$AGENT_PUSH_HOOK"; : > "$PUSHES"
  nb=$(date -u -d "$(openssl x509 -in "$EGRESS_CERT_FILE" -noout -startdate | cut -d= -f2)" +%s 2>/dev/null \
    || date -u -j -f '%b %e %T %Y %Z' "$(openssl x509 -in "$EGRESS_CERT_FILE" -noout -startdate | cut -d= -f2)" +%s)
  DAY=86400
}

@test "cert-check: silent while more than 1/3 of the lifetime is left, one push below it, none again for the same cert" {
  check_setup                                            # 90-day certificate
  EGRESS_NOW=$((nb + 59 * DAY)) run "$REPO/bin/egress-cert-check"; [ "$status" -eq 0 ]; [ ! -s "$PUSHES" ]   # 31 days left > 30
  EGRESS_NOW=$((nb + 61 * DAY)) run "$REPO/bin/egress-cert-check"; [[ "$output" == *ALERT* ]]               # 29 days left < 30
  [ "$(jq -r .notification_type "$PUSHES")" = agent_needs_input ]
  EGRESS_NOW=$((nb + 80 * DAY)) run "$REPO/bin/egress-cert-check"; [ "$(jq -s length "$PUSHES")" -eq 1 ]
}

@test "cert-check: a missing certificate only logs" {
  check_setup; rm "$EGRESS_CERT_FILE"
  run "$REPO/bin/egress-cert-check"; [ "$status" -eq 0 ]; [[ "$output" == *"no certificate"* ]]; [ ! -s "$PUSHES" ]
}

# --- wiring -----------------------------------------------------------------------------------------------------------
@test "gost.yaml reads the mounted certificate and compose mounts it; the fallback entrypoint drops exactly that block" {
  grep -qE '^      certFile: /etc/gost/tls/cert.pem' "$E/gost.yaml" && grep -qE '^      keyFile: /etc/gost/tls/key.pem' "$E/gost.yaml"
  grep -q '/tls:/etc/gost/tls:ro' "$E/compose.yaml"
  run sed '/^    tls:/,/keyFile/d' "$E/gost.yaml"
  [[ "$output" != *certFile* && "$output" != *keyFile* ]]
  [[ "$output" == *"type: tls"* ]]
  [ "$(diff <(cat "$E/gost.yaml") <(printf '%s\n' "$output") | grep -c '^<')" -eq 3 ]
}

@test "launchd agent runs the libexec copy daily and is valid" {
  p="$REPO/config/mac/launchd/cc-orchestrator.claude.egress-cert.plist.tmpl"
  plutil -lint "$p" >/dev/null 2>&1 || ! command -v plutil >/dev/null
  grep -q 'libexec/cc-orchestrator/egress-cert-renew' "$p"; grep -q StartCalendarInterval "$p"
}

@test "units: cert expiry check runs with the bytes alert; cc-egress warns about a missing certificate" {
  grep -q '^ExecStartPost=.*egress-cert-check' "$REPO/config/cloud/systemd/cc-egress-bytes.service"
  grep -q 'ExecStartPre=.*WARNING no TLS certificate' "$REPO/config/cloud/systemd/cc-egress.service"
}

@test "no ACME or Cloudflare token appears in git-tracked egress files" {
  ! grep -rnE 'CLOUDFLARE_DNS_API_TOKEN=[A-Za-z0-9_-]{20,}|cf-token' "$E" "$REPO/bin/egress-cert-renew" "$REPO/bin/egress-cert-check"
}

@test "cloud never holds DNS-edit power: nothing cloud-side references the token or lego" {
  ! grep -rnE 'cc-cf-acme-dns-token|lego|CLOUDFLARE_DNS' "$E" "$REPO/bin/egress-cert-check" "$REPO/config/cloud/systemd"
}
