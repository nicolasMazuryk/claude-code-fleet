# Phase 2 — Network: Tailscale on cloud (oci PR + tailnet policy)

Date: 2026-10-14 · Branch: `phase-2-network` (stacked on `phase-1-capture`) · oci PR: nicolasMazuryk/oci-infra#1
(`feat/tailscale-cloud`, worktree `~/Documents/oci/.claude/worktrees/tailscale`)

## Done
- **oci PR** (draft):
  - `bootstrap.sh` installs mosh and gains `setup_tailscale`:
    - apt repo
    - tailscaled state on `/data/core/tailscale` via a drop-in
    - `tailscale up --ssh --hostname=cloud --advertise-tags=tag:cloud --accept-dns=false --auth-key=file:…` only when
      the node has no state; a joined node only gets `tailscale set`
    - never fatal; skips until the Vault secret exists
  - `allow_udp_on_iface tailscale0 60000:61000` in `lib.sh` (live + `rules.v4`, before REJECT, idempotent).
  - oci docs: access-ssh, CLAUDE.md (pointer to cc-orchestrator, secrets, invariant note), architecture,
    first-deploy, secrets-rotation, wipe-and-restore, troubleshooting, fleet-repos.
- **`config/tailscale/policy.hujson`**:
  - `tag:cloud` owned by `autogroup:admin`
  - members → `*:*` + `autogroup:internet:*` (exit node `static-ip`)
  - no rule from `tag:cloud`
  - ssh accept members → `tag:cloud` as `agent`, `ubuntu`
  - default `autogroup:self` check rule kept
  - `tests`/`sshTests` so Tailscale rejects a save that breaks the invariants
  - node list and the Mac rename recorded in comments
- **`tests/tailscale-policy.bats`** (3 tests): hujson parses; invariants hold; the checker catches an allow-all
  `grants` rule and an `acls` rule from `tag:cloud`.
- **Docs**:
  - new `docs/runbooks/tailscale.md`: ordered human procedure (policy → key → host-sync → Mac rename) and checks
  - verify.md rows 1–1i
  - spec §3.1/§5, ADR 0001 implementation notes, architecture
  - cloud-rebuild, mac-rebuild, 00-bootstrap, rotate-secrets, troubleshooting, README index
- Mac: `brew install mosh` (1.4.0), needed for the verify step. tmux and the rest stay Phase 3.

## Verified
- `make lint` → `lint: ok (4 files)`; `make test` → 16/16 ok.
- oci: `bash -n` + shellcheck show no new findings. `setup_tailscale` was run against mocks for Running / Stopped /
  NeedsLogin / no secret, with the expected calls. The key goes only through `file:` and the temp file is removed.
- oci `rules.v4` edit: run twice on a scratch copy of the live file on the VM. The rule appears once, before
  `-A INPUT -j REJECT`, and `iptables-restore --test` passes. Nothing on the VM was changed.
- Facts re-checked on the VM (Bastion, read-only):
  - Ubuntu noble aarch64, `iptables-persistent` installed, INPUT ends in REJECT
  - no tailscale or mosh yet
  - exactly one `agent@offers-pipeline` active
- Facts re-checked on the Mac:
  - Tailscale 1.102.3, node `nicolas-macbook`, untagged, login `user@github`
  - tailnet `example.github`, MagicDNS on
  - exit node `static-ip` (member, untagged) in use
  - no other peers
- Phase verify items (`ssh`/`mosh agent@cloud`, ACL check from cloud, Bastion) are **blocked** on the human steps below.

## Findings / deviations from the plan
- The current tailnet policy cannot be read without an admin-console session or API key. The file assumes the default
  policy. The human merges anything extra (runbook §1), and the policy `tests` make Tailscale reject a leftover allow-all.
- Plain `tailscale ping` from cloud may get a pong from the Mac even with the ACL in place (disco runs below the packet
  filter). The verify step uses `tailscale ping --icmp`.
- Until Phase 3 writes `Host cloud` (`User agent`) to `~/.ssh/config`, `ssh cloud` logs in as `nicolas`, which the
  policy denies. The Phase 2 checks use `agent@cloud`.
- `make ssh VM=app CMD='a; b'` splits on `;` locally (the Makefile does not quote `$(CMD)`). Use `scripts/ssh.sh app '…'`.
- Auth keys expire (≤ 90 days). Superseded on 2026-10-15: Vault now holds a non-expiring OAuth client secret.
- `static-ip` is a member device, so it can reach the Mac and cloud (as it could under allow-all). It could be tagged
  later; that is out of scope here.

## Verified live (2026-10-15, after oci-infra#1 merged and host-synced; recorded in Phase 3b)
- `cloud` = 100.64.0.10, `tag:cloud` (tagged-devices) on the tailnet.
- Row 1: `ssh agent@cloud` works over Tailscale SSH and prints `agent@app`; mosh prints `MOSH_OK` (non-interactive
  mosh needs a terminal size, see verify row 1).
- Row 1a: `tailscale ping --icmp cloud` → pong. Row 1b: cloud → `macbook` ICMP ping times out (ACL blocks it).
- Row 1i: VM iptables INPUT rule #7 `-i tailscale0 -p udp --dport 60000:61000 -j ACCEPT` sits before the REJECT and is
  persisted once. A second `host-sync` is a no-op (`tailscale up as cloud.tailnet-example.ts.net.`).
- Row 1d: the exit node `static-ip` still works (public IP 178.104.255.141); the Mac node is `macbook`.
- Row 1c: Bastion break-glass `make ssh VM=app CMD=true` → rc 0.
- Row 1j: the macOS Application Firewall (on, stealth) allows `mosh-client` and `mosh-server` (Cellar realpaths).
- The join credential is now a non-expiring OAuth client secret (no rotation); the 90-day key was revoked. See
  [ADR 0001](../decisions/0001-tailscale-on-oci.md) and [rotate-secrets](../runbooks/rotate-secrets.md).

## Outstanding (human) — all done by 2026-10-15
In order, as in [runbooks/tailscale.md](../runbooks/tailscale.md):
1. Merge the live policy into the file and apply it.
2. Generate the auth key and `secret-put` it.
3. Optionally create and `secret-put` the ntfy topic.
4. Merge the oci PR and run `make host-sync VM=app`.
5. Rename the Mac node to `macbook`.
6. Run the verify rows 1–1i.
