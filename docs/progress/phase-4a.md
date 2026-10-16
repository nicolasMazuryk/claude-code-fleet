# Phase 4a — Rename the OCI VM `app` → `cloud`

Date: 2026-10-16 · Branch: `phase-4a-rename-cloud` (from `main` after PR #6) · oci: `feat/rename-app-to-cloud`
(nicolasMazuryk/oci-infra-old#2; `oci-infra` redirects there).

Prerequisite of Phase 4. Owner's decisions (final): rename the A1 VM to `cloud` everywhere in oci. That covers the OS
hostname, the VNIC `hostname_label`, display names, Terraform addresses (via `moved {}`, zero destroys), `host/cloud/`,
`VM=cloud`, Kuma, docs and variables. `ops` is unchanged. The Mac's hostname is `nicolas-macbook`, and its Tailscale
node stays `macbook`.

## Done
- **oci (PR #2):**
  - `terraform/core`:
    - display names `core-vm-cloud`, `core-vnic-cloud` (label `cloud`), `core-bv-cloud-data`, `core-nsg-cloud`,
      `core-log-cloud`, `core-uac-cloud` and `core-alarm-cloud-{cpu,mem,disk}`
    - role tags, addresses, variables `cloud_*` (values unchanged) and outputs
    - `moved.tf` with 17 moves
  - Exception: the volume attachment keeps `display_name = "core-att-app-data"`. That field is ForceNew. With it
    renamed, the plan was `1 to add, 10 to change, 1 to destroy`: the attachment would be replaced, which detaches
    `/data`. Kept and documented in oci CLAUDE.md.
  - `host/app` → `host/cloud`. Bootstrap step 0 pins the OS hostname:
    - `/etc/hosts` gets `127.0.1.1 cloud cloud`
    - `hostnamectl set-hostname cloud`
    - the cloud-init drop-in `99-zz-core-hostname.cfg` (`hostname`/`fqdn: cloud`) is needed. The image has
      `preserve_hostname: false`, and Oracle's `manage_etc_hosts: localhost` re-applies the IMDS name (`app`) on
      every boot.
  - Live `core.env` is never re-shipped. `lib.sh` maps `APP_IP`/`ROLE=app`, and `migrate_core_env` rewrites the file
    once on both VMs.
  - Kuma: the origin monitor is renamed in place (`renamedFrom`, keeps its history). If that fails, the new monitor
    is created instead.
  - `make ssh CMD=` fix: `$(CMD)` was unquoted, so `CMD='a; b'` ran `b` on the Mac. Found while inspecting the VM;
    phase-2 had noted it as a quirk. CMD is now passed as one quoted argument.
- **cc-orchestrator:**
  - `core-vm-app` / `VM=app` / `host/app` / `core-bv-app-data` replaced in CLAUDE.md, README, architecture,
    ADR 0001/0002, spec, runbooks (00-bootstrap, add-repo, cloud-rebuild, rotate-secrets, tailscale, troubleshooting)
    and the policy comment
  - Real-names row for OS hostnames (`nicolas-macbook` / `cloud`)
  - mac-rebuild: `scutil` hostname step
  - verify rows 1k–1m
  - plan.md note
  - Historical progress logs are unchanged.
  - The Mac's OS hostname is `nicolas-macbook`; no other hostname variants of the Mac appeared in the repo. The name
    remains in docs as the *former Tailscale node name* ("was …"), which is still accurate.

## Verified (before merge)
- `make plan-core` (oci branch): **`Plan: 0 to add, 10 to change, 0 to destroy.`**
  - In-place updates only: display names, role tags, `hostname_label "app" -> "cloud"`, alarm bodies and the
    `ops_in_kuma` description.
  - The other resources print `has moved to`.
- `make plan-all`: foundation `no changes`, cloudflare `no changes`, core `CHANGES PENDING` (the 10 above).
- Live VM (read-only, `ssh agent@cloud`):
  - `hostname` → `app`
  - `/etc/cloud/cloud.cfg` has `preserve_hostname: false`; `99-oracle-compute-infra-datasource.cfg` has
    `manage_etc_hosts: localhost`
  - IMDS `instance/hostname` → `app`
  - `/etc/hosts` has `127.0.1.1	app	app`
  - `agent@offers-pipeline` `active`
- `make ssh VM=cloud CMD='hostname; echo REMOTE_OK'` (new bastion.sh) → `app`, `REMOTE_OK`, both remote.
  - A brand-new Bastion session rejects the key for its first ~minute (`Permission denied (publickey)`); a retry
    works. This is known behaviour, not a regression.
- `/etc/hosts` rewrite logic tested locally against the live tab format: 1st run changes, 2nd run no change.
- oci: `terraform fmt -check` ok, `bash -n`, `node --check`, shellcheck (no new warnings).
- cc-orchestrator: `make lint` → `lint: ok (14 files)`; `make test` → 34/34 ok.
- Sites before: `https://mazuryktech.com` → `HTTP/2 200`; `status.mazuryktech.com/status/core` → `200`.

## Outstanding (human; the auto-mode classifier denied the PR merge, so nothing was merged or applied)
1. Merge oci-infra-old#2 and this PR (#7), then
   `git -C ~/Documents/oci pull --ff-only && git -C ~/Documents/cc-orchestrator pull --ff-only`.
2. `cd ~/Documents/oci && make plan-core`: confirm `0 to add, 10 to change, 0 to destroy`, then `make apply-core`.
3. Run `make host-sync VM=cloud` twice.
   - The 1st run logs `core.env: renamed …`, `cloud-init hostname drop-in written`, `/etc/hosts: …` and
     `OS hostname set to cloud`.
   - The 2nd run logs none of these.
4. Run `make host-sync VM=ops`, needed for three changes:
   - the Kuma monitor rename (expect `[kuma] renamed monitor: core-vm-app origin … -> core-vm-cloud origin …`)
   - `CLOUD_IP`
   - `core-nsg-cloud` in the weekly drift cron
5. Verify: verify.md rows 1k–1m.
6. Optional, on the owner's approval only: `ssh agent@cloud 'sudo reboot'`, then `ssh agent@cloud hostname` → `cloud`.
- `agent@offers-pipeline` is untouched. Its Remote Control device name stays `app` until it restarts (Phase 4b
  replaces it).

## Post-merge
_To be filled by the session that verifies after the steps above._
