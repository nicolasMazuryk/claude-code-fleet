# Rebuild cloud (`core-vm-cloud`) — the one rebuild path

Machine = oci repo (`~/Documents/oci-free-tier-platform`); Claude Code = this repo ([ADR 0002](../decisions/0002-ownership-split.md)).
The path is always: **oci (`make restore` or `make host-sync VM=cloud`) → `./install.sh cloud` here (from the Mac)**.
Both steps are idempotent and can be re-run in any order afterwards: oci's bootstrap never touches `cc-*` units, and
`install.sh cloud` never touches the machine layer (verified 2026-10-16, Phase 4b: host-sync after install left
`cc-rc@offers-pipeline` and `cc-agents` with the same PID, start time and restart count).

## Facts
- `core-vm-cloud`: A1.Flex 2 OCPU / 12 GB, Ubuntu 24.04 arm64, uk-london-1, private IP `10.0.2.10`, **no public IP**.
- OS hostname `cloud` (pinned by oci bootstrap step 0; it is the Remote Control device name). The VM was `app` until
  2026-10-16 (oci `terraform/core/moved.tf`).
- Persistent `/data` (100 GB, `core-bv-cloud-data`): `/data/home/agent` (agent home: claude + gh logins,
  `~/.claude.json` with Remote Control acceptance and workspace trust, `~/claude-code-fleet`), `/data/fleet/<repo>`.
  Units (`/etc/systemd/system/cc-*`) are on the boot volume, so a restore needs `install.sh cloud` again.
- Access: Tailscale `cloud` (`tag:cloud`) as `agent`; break-glass OCI Bastion `cd ~/Documents/oci-free-tier-platform && make ssh VM=cloud`.
- Free-tier block storage is full (200/200 GB): never add volumes.

| Who installs what | oci (`host/cloud/bootstrap.sh`) | this repo (`./install.sh cloud`) |
|---|---|---|
| VM, `/data`, swap, packages (git, tmux, mosh, jq, gh, rsync, Node 24 + corepack) | ✓ | |
| `agent` user, passwordless sudo, docker group, linger, git identity, gh auth (Vault PAT) | ✓ | linger re-checked |
| Tailscale `cloud` + mosh iptables rule; Vault secrets; log shipping of `/var/log/core/agent.log` | ✓ | |
| Claude Code binary (`~/.local/bin/claude`, native installer, self-updating) | | ✓ |
| `bin/` links, `~/.config/cc-orchestrator/config`, `~/.tmux.conf`, PATH line in `~/.bashrc` | | ✓ |
| `~/.claude` settings, CLAUDE.md, skills, hooks, plugins (`cc-sync-settings`) | | ✓ |
| `cc-agents.service` (Agent View, tmux `fleet`), `cc-rc@<repo>.service`, rsyslog rule `30-cc-orchestrator.conf` | | ✓ |
| repos in `config/cloud/repos.txt` cloned into `/data/fleet` | | ✓ |
| removing the legacy oci `agent@<repo>` / `agent@.service` / `/usr/local/bin/fleet` | ✓ (step 5) | ✓ (kept for `--rollback`) |

## Steps
1. `[H]` Tailnet policy from `config/tailscale/policy.hujson` applied (Phase 2). Join credential in Vault
   `core-secret-tailscale-authkey`: a non-expiring OAuth client secret (`tag:cloud`), never rotated
   ([tailscale](tailscale.md) §1–2). Tailscale state is on `/data`, so a restore from backup rejoins as `cloud`
   without it. On a fresh `/data` (`BACKUP=none`), first delete the old `cloud` machine in the admin console.
2. `[H]` Machine, in `~/Documents/oci-free-tier-platform`:
   - after a wipe: `make restore BACKUP=<ocid>|none` (oci runbook `wipe-and-restore.md`); cloud-init runs the bootstrap;
   - on an existing VM: `make host-sync VM=cloud`.
3. From the Mac: `ssh cloud true` (checks in [tailscale](tailscale.md) §5).
4. Claude Code, from the Mac, in the live checkout:
   ```bash
   cd ~/Documents/claude-code-fleet
   ./install.sh cloud --dry-run     # what would change; writes nothing on cloud (except a staging copy in ~/.cache)
   ./install.sh cloud               # = make install-cloud; a 2nd run prints "install.sh cloud-local: no changes"
   ```
   It rsyncs this checkout to `~/claude-code-fleet`, copies the ntfy topic, runs `install.sh cloud-local` on cloud
   (binary, links, config, legacy removal, units, linger, clones, `cc-agents`, `rc-servers`), then `cc-sync-settings`
   (must end with `4 macOS-only hook handler(s) relayed`). Missing plugins: `bin/cc-sync-settings --install-plugins`.
5. `[H]` One-time interactive steps, only if `/data/home/agent` is new (all persist on `/data` in
   `~/.claude.json`/`~/.claude/.credentials.json`; a restore from backup keeps them):
   - login: `ssh -t cloud 'claude auth login'` (full claude.ai login; API keys don't work with Remote Control);
   - Remote Control acceptance (one global `remoteDialogSeen` in `~/.claude.json`):
     `ssh -t cloud 'cd /data/fleet/offers-pipeline && claude remote-control'` → `y` → Ctrl+C;
   - workspace trust for Agent View's root: `ac` → "Yes, I trust this folder" (for `/data/fleet`);
   - workspace trust per allowlisted repo: `ssh -t cloud 'repo-init <repo>'` → accept → `/exit`. `rc-servers` only
     starts `cc-rc@<repo>` for trusted repos (an untrusted one would crash-loop), so it starts here.
6. Checks: [verify.md](verify.md) rows 3–3h and 6; `make doctor` (Phase 7).
7. Reboot test (`[H]`, approval): `ssh cloud 'sudo reboot'`, wait ~1 min, then
   `ssh cloud 'systemctl is-active cc-agents; systemctl list-units "cc-rc@*" --no-legend; tmux ls'`.

## Rollback (to the legacy oci `agent@<repo>` setup)
`./install.sh cloud --rollback` stops and removes `cc-rc@*`, `cc-agents` and the rsyslog rule, and restores
`agent@.service`, `/usr/local/bin/fleet` and the `agent@<repo>` instances from the copy kept in
`~/.local/state/cc-orchestrator/legacy` on cloud (tested in `tests/install-cloud.bats`). The next oci host-sync removes
`agent@` again unless oci PR #3 is reverted first. Forward again: `./install.sh cloud`.

## Gotchas
- **"This folder is already served by a terminal `claude remote-control` on this device"** in
  `journalctl -u cc-rc@<repo>`: a previous server for that folder is still registered server-side. A server killed
  without a clean shutdown (e.g. legacy `tmux kill-server`) stays registered for ~3–4 min; `cc-rc@` retries every 30 s
  and connects by itself. systemd's SIGTERM deregisters cleanly, so `cc-rc@` restarts don't hit this.
- `cc-rc@` runs **headless** (no tmux, no pty): verified 2026-10-16 with a transient unit (`StandardInput=null`) that
  reached `✔ Ready` and deregistered on SIGTERM. There is nothing to attach to; use `fleet logs cloud <repo>`.
- Claude Code self-updates on cloud; running servers keep the old version until restarted
  ([upgrade-claude-code](upgrade-claude-code.md)).
