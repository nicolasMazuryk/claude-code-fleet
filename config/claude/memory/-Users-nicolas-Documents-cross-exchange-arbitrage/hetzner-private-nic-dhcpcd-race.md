---
name: hetzner-private-nic-dhcpcd-race
description: "On fresh Hetzner provision, slow-booting boxes miss the private-NIC DHCP lease; WG bootstrap fails until dhcpcd is run by hand"
metadata:
  type: project
---

ArbiNet clean-slate provision (task 16): after `terraform apply`, the WireGuard
bootstrap play (`--tags baseline,wireguard`) failed on **core (cpx62)** and
**obs (cpx42)** with `No interface carrying 10.0.1.x found — cannot set up the
WG gateway NAT`, while **hot (ccx13)** succeeded.

**Root cause:** the private NIC `enp7s0` is left `unmanaged` by netplan/networkd
on all 3 boxes (netplan `50-cloud-init.yaml` configures only `eth0`). The private
`10.0.1.x` lease is held by **`dhcpcd`**, launched by Hetzner's
`hc-net-ifup@enp7s0.service`. On the bigger/slower core+obs, `enp7s0` appeared
after that launcher ran → no dhcpcd → `enp7s0` stayed DOWN, no IP. Fast-booting
hot won the first-boot race.

**Fix (per box, over public IP SSH):** `sudo dhcpcd enp7s0` — brings the link up,
leases `10.0.1.x` from `10.0.0.1`, adds the `10.0.0.0/16` route. Reproduces hot's
exact running state. Then re-run the bootstrap play (idempotent). A reboot may
also fix it but is a coin-flip on the same race; `dhcpcd enp7s0` is deterministic.

**PERMANENT FIX SHIPPED (commit f18c84c, branch nicolasMazuryk/interview-before-task).**
The manual `sudo dhcpcd enp7s0` is now superseded by a cloud-init-delivered,
device-triggered systemd unit `hc-private-nic-up@.service` (in
`infra/terraform/modules/host/cloud-init.yaml.tftpl`, iface via new
`private_iface` var). It runs `dhcpcd --ipv4only --waitip=4 enp7s0`,
`Type=oneshot` + `RemainAfterExit=yes`, `WantedBy=sys-subsystem-net-devices-<iface>.device`.
Companion: the ansible `wireguard` role re-gathers net facts with `until/retries`
(prefix-matched) before resolving the NIC.

**Two design points proven on real boxes (full destroy+apply, both race outcomes):**
- `--ipv4only` is load-bearing: Hetzner's `hc-net-ifup@` runs `dhcpcd --ipv4only`
  (control socket `<iface>-4.sock`). A default dual-stack dhcpcd uses a *different*
  socket (`<iface>.sock`), does NOT detect Hetzner's instance → BOTH run (verified
  two masters on the race-winner). Matching `--ipv4only` shares the socket → our
  start no-ops when Hetzner won, sole client when it lost.
- `Type=oneshot` not `forking`: on the race-winner our no-op exit forks no daemon,
  which `Type=forking` reads as `failed` (verified). oneshot+RemainAfterExit stays
  active. Renewal intact — on the race-loser `dhcpcd --waitip=4` still backgrounds
  its own renewing daemon (only dhcpcd's `--oneshot` FLAG drops renewal; not passed).

**Random init-local `status: error` — ROOT-CAUSED + FIXED (commit c735ddd, same branch).**
The random per-provision `status: error` (init-local `network-config-v1` schema fail /
IMDS `NoneType`) is **cloud-init bug #6862**: `DataSourceHetzner` sets `ipv6=True`, so
init-local tries IPv6 *via DHCP* on the public NIC; Hetzner serves IPv6 by metadata not
DHCP, so a slow early IMDS fetch makes the network render throw. Cosmetic (fallback DHCP
still brings the box up) but makes `cloud-init status` an unreliable success signal.
**Fix** (in `cloud-init.yaml.tftpl`): a `write_files` drop-in
`/etc/cloud/cloud.cfg.d/99-arbinet-disable-network.cfg` → `network: {config: disabled}`
(cloud-init owns no NIC here — `eth0` rides the fallback netplan, `enp7s0` the dhcpcd unit)
+ a top-level `power_state: {mode: reboot, condition: true}` so boot #2's init-local re-runs
with the drop-in present. **user_data cannot fix boot #1 inline** — cloud-init ignores
user-data for network config (precedence: datasource → cloud.cfg.d → kernel cmdline), and
write_files lands in the *config* stage, after init-local. One reboot only (not a loop).
**Verified on full destroy→apply (3 boxes):** all 3 `cloud-init status: done`, `errors: []`,
reachable on public `eth0`, `enp7s0` = `10.0.1.{10,20,30}`, `hc-private-nic-up@` active,
`site.yml --tags baseline,wireguard` `failed=0`, wg0 up. NOTE: public NIC is **`eth0`** on
these boxes, not `enp1s0`.

**Why:** capstone bring-up assumed the private net "just comes up"; it doesn't on
slow boxes. **How to apply:** the fix is automatic on next from-zero provision — no
manual `dhcpcd` step. user_data only applies at instance create, so it activates on
the next fresh apply (the live env at fix time was destroyed). Related: the
`operator_ips` firewall-drift check and [[worktree-context-ephemeral]].
