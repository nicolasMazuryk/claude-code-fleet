# 0001 — Cloud access via Tailscale on core-vm-app

- Status: accepted (2026-10, confirmed with user)
- Plan: Phase 2

## Context
The spec assumes a VM reachable on port 22 with Tailscale. `core-vm-app` has **no public IP**, is reachable only
through OCI Bastion, and the oci repo forbids public IPs and `0.0.0.0/0` ingress. mosh, `fleet`, the sound relay,
presence beacon and settings sync all need a cheap, always-on Mac → cloud path; Bastion sessions expire after 3 h and
take ~30 s to create.

## Decision
Install Tailscale on `core-vm-app` (in the oci bootstrap): `tailscale up --ssh --hostname cloud
--advertise-tags=tag:cloud --authkey $(secret_get core-secret-tailscale-authkey)`. The auth key is reusable and
tagged, stored only in OCI Vault, so a rebuilt VM rejoins under the same name. mosh is allowed by an iptables rule on
`tailscale0` only (UDP 60000–61000), inserted before Ubuntu's REJECT and persisted. Bastion stays as break-glass.

The tailnet policy (`config/tailscale/policy.hujson`) adds `tag:cloud`; members → `*:*`; **no rule with
`src: tag:cloud`**; Tailscale SSH: members → `tag:cloud` as `agent`, `ubuntu`. Existing rules (exit node `static-ip`)
are merged, not replaced. The Mac node is renamed `macbook`.

## Consequences
- Tailscale is outbound-only (DERP/UDP hole punching): OCI invariants (no public IP, no open ingress) still hold.
- Login to cloud is by tailnet identity; no SSH keys for cloud on the Mac or phone.
- Cloud cannot initiate anything toward the Mac/iPhone; everything is Mac-initiated.
- A compromised tailnet admin account now also reaches cloud (acceptable; same account already controls the exit node).
