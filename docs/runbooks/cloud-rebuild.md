# Rebuild cloud (`core-vm-cloud`)

Status: skeleton. Machine = oci repo; Claude Code = this repo ([ADR 0002](../decisions/0002-ownership-split.md)).

## Facts
- `core-vm-cloud`: A1.Flex 2 OCPU / 12 GB, Ubuntu 24.04 arm64, uk-london-1, private IP `10.0.2.10`, **no public IP**.
- OS hostname `cloud` (VNIC label `cloud`; pinned by oci bootstrap step 0 via the cloud-init drop-in
  `/etc/cloud/cloud.cfg.d/99-zz-core-hostname.cfg`). The Claude app shows it as the Remote Control device name.
  The VM was named `app` until 2026-10-16 (oci `terraform/core/moved.tf`). A Remote Control server started before that
  keeps the old device name until it restarts.
- Persistent `/data` (100 GB, `core-bv-cloud-data`): `/data/home/agent` (agent home, claude + gh logins), `/data/fleet/<repo>`.
- Access: Tailscale `cloud` (`tag:cloud`), break-glass OCI Bastion `cd ~/Documents/oci && make ssh VM=cloud`.
- Free-tier block storage is full (200/200 GB): never add volumes.

## Steps
1. `[H]` Tailnet policy from `config/tailscale/policy.hujson` applied (Phase 2). Join credential in Vault
   `core-secret-tailscale-authkey`: a non-expiring OAuth client secret (`tag:cloud`), never rotated. See [tailscale](tailscale.md) §1–2.
   Tailscale state is on `/data`, so a restore from backup rejoins as `cloud` without the key. On a fresh `/data`
   (`BACKUP=none`), first delete the old `cloud` machine in the admin console.
2. `[H]` VM from the oci repo: `make restore BACKUP=<ocid>|none` (after a wipe) — oci runbook `wipe-and-restore.md`.
   Bootstrap installs packages, Node, `agent`, gh auth, Tailscale (`--hostname cloud`), mosh iptables rule.
   On an existing VM, oci changes ship with `[H]` `make host-sync VM=cloud`.
3. From the Mac: `ssh agent@cloud true` (`ssh cloud true` once Phase 3 wrote `~/.ssh/config`); checks in [tailscale](tailscale.md) §5.
4. `./install.sh cloud` (Phase 4): rsync repo → `/data/home/agent/cc-orchestrator`, symlink `bin/`, config, units
   `cc-agents` + `cc-rc@`, migrate `agent@*` → `cc-rc@*`, tmux.conf, ntfy topic, `cc-sync-settings`.
5. `[H]` if not already on `/data`: `ssh -t cloud 'claude auth login'`; accept Remote Control once
   (`ssh -t cloud 'cd /data/fleet/<repo> && claude remote-control'` → `y` → Ctrl+C).
6. `ssh -t cloud 'repo-init <repo>'` for each repo in `config/cloud/repos.txt` ([add-repo](add-repo.md)).
7. `make sync` → "4 … relayed"; [verify.md](verify.md) cloud section; `make doctor`.
8. Reboot test: `ssh cloud 'sudo reboot'`, wait, `ssh cloud 'systemctl is-active cc-agents "cc-rc@*"'`.
