#!/bin/sh
# guard.sh — runs in the guard container (shared egress namespace): load guard.nft when the table is missing, keep the
# reply-routing rule in place. Re-checked every 10 s, so it survives flushes; it never reloads an existing table, which
# keeps the egress_bytes counter. A failure here leaves the healthcheck red and gost stopped (fail closed).
set -eu
while :; do
  nft list table inet egress_guard >/dev/null 2>&1 || nft -f /etc/guard.nft
  ip rule show | grep -q 'fwmark 0x2/0x2' || ip rule add fwmark 0x2/0x2 lookup main priority 5100
  sleep 10
done
