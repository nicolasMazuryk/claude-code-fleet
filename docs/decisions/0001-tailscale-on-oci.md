# 0001 — Cloud access via Tailscale on core-vm-cloud

- Status: accepted (2026-10, confirmed with user)
- Plan: Phase 2

## Context
The spec assumes a VM reachable on port 22 with Tailscale. `core-vm-cloud` has **no public IP**, is reachable only
through OCI Bastion, and the oci repo forbids public IPs and `0.0.0.0/0` ingress. mosh, `fleet`, the sound relay,
presence beacon and settings sync all need a cheap, always-on Mac → cloud path; Bastion sessions expire after 3 h and
take ~30 s to create.

## Decision
Install Tailscale on `core-vm-cloud` (in the oci bootstrap): `tailscale up --ssh --hostname cloud
--advertise-tags=tag:cloud --authkey $(secret_get core-secret-tailscale-authkey)`. The credential is reusable and
tagged (since 2026-10 a non-expiring OAuth client secret, see below), stored only in OCI Vault, so a rebuilt VM rejoins under the same name. mosh is allowed by an iptables rule on
`tailscale0` only (UDP 60000–61000), inserted before Ubuntu's REJECT and persisted. Bastion stays as break-glass.

The tailnet policy (`config/tailscale/policy.hujson`) adds `tag:cloud`; members → `*:*`; **no rule with
`src: tag:cloud`**; Tailscale SSH: members → `tag:cloud` as `agent`, `ubuntu`. Rules already live in the
tailnet are merged, not replaced. The Mac node is renamed `macbook`.

## Consequences
- Tailscale is outbound-only (DERP/UDP hole punching): OCI invariants (no public IP, no open ingress) still hold.
- Login to cloud is by tailnet identity; no SSH keys for cloud on the Mac or phone.
- Cloud cannot initiate anything toward the Mac/iPhone; everything is Mac-initiated.
- A compromised tailnet admin account now also reaches cloud (acceptable; the same account already controls every node).

## Implementation notes (Phase 2)
- The key is passed as `--auth-key=file:<0600 tmp>`, never on argv. It is read only when the node has no state.
  On later bootstrap runs a joined node only gets `tailscale set` (no re-auth).
- tailscaled state lives on `/data/core/tailscale` (drop-in `tailscaled.service.d/10-core-state.conf`,
  `RequiresMountsFor=/data`). A restore from backup therefore keeps the node identity, so `cloud` never becomes `cloud-1`.
- `--accept-dns=false` on cloud: the VM keeps OCI's resolver (Vault, apt, Docker). Cloud never needs tailnet names.
- The policy carries `tests`/`sshTests`, so the "no `src: tag:cloud`" invariant is enforced by Tailscale on save,
  and by `tests/tailscale-policy.bats` in this repo.
- Plain `tailscale ping` (disco) from cloud can still get a pong from the Mac: disco runs below the ACL. The check is
  `tailscale ping --icmp`, which the ACL drops.
- Join credential (2026-10, owner's decision): the 90-day auth key was replaced by a **Tailscale OAuth client
  secret** (scope `Auth Keys: Write`, tag `tag:cloud`) stored in the same Vault secret as
  `tskey-client-…?ephemeral=false&preauthorized=true`. It does not expire, so no rotation or refresh procedure exists;
  it is replaced only if it leaks or the OAuth client is deleted. The old auth key was revoked.
- Verified live 2026-10-15: `cloud` 100.64.0.10 (`tag:cloud`); Mac → cloud ICMP pong; cloud → `macbook` ICMP
  times out; mosh works; a second `host-sync` is a no-op.
