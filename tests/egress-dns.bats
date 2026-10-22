#!/usr/bin/env bats
# egress-dns.bats — gost resolves through public DoH, because the guard drops Docker's loopback resolver for uid 10001.

setup() {
  REPO="$BATS_TEST_DIRNAME/.."
  E="$REPO/config/cloud/egress"
}

@test "gost.yaml: the service uses a public DoH resolver (tcp 443), not Docker's loopback resolver" {
  grep -qE '^  resolver: egress-dns' "$E/gost.yaml"
  grep -qE '^- name: egress-dns' "$E/gost.yaml"
  grep -qE '^  - addr: https://(1\.1\.1\.1|9\.9\.9\.9)/dns-query' "$E/gost.yaml"
  ! grep -qE 'addr: (127\.|udp://|tls://)' "$E/gost.yaml"
}

@test "guard drop sets are unchanged: five skuid rules, no loopback exemption" {
  [ "$(grep -cE '^[[:space:]]*meta skuid' "$E/guard.nft")" -eq 5 ]
  ! grep -E '^[[:space:]]*meta skuid' "$E/guard.nft" | grep -E 'accept' | grep -q '127\.'
}

@test "gost entrypoint's tls-stripping sed leaves the resolver intact" {
  sed '/^    tls:/,/keyFile/d' "$E/gost.yaml" | grep -qE '^  resolver: egress-dns'
}
