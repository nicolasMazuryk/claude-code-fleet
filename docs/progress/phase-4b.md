# Phase 4b — Cloud runtime + removal of the legacy oci Claude Code setup

Date: 2026-10-16 · Branch: `phase-4b-cloud-runtime` (from `main` after PR #7) · oci: `feat/claude-code-to-cc-orchestrator`
(nicolasMazuryk/oci-infra-old#3).

## Done
- **cc-orchestrator**
  - `./install.sh cloud [--dry-run | --rollback]` (Mac) → rsync to `cloud:~/cc-orchestrator`, ntfy topic, `install.sh
    cloud-local` over ssh, `cc-sync-settings`. `cloud-local` steps: claude binary (this repo now owns it), bin links
    (not the Mac-only `cc-capture`, `cc-sync-settings`, `cc-orchestrator-start`), PATH line atop `~/.bashrc`
    (Ubuntu's returns early for non-interactive ssh), config, tmux.conf, legacy removal (kept for `--rollback`), units +
    rsyslog rule, linger, clone `config/cloud/repos.txt`, `repo-init --no-trust` each, `cc-agents`, `rc-servers`.
  - `config/cloud/{config.tmpl, systemd/cc-rc@.service, systemd/cc-agents.service, rsyslog-cc-orchestrator.conf}`.
  - `rc-serve` execs claude once under systemd; `rc-servers` (cloud) only enables cloned **and trusted** repos and stops a
    running `agent@<repo>` first.
  - `cc-sync-settings` (transform + mirror + plugins, `--dry-run`, `--print`, `--install-plugins`), `cc-relay-hook`.
  - bats: `cc-sync-settings.bats` (fixture → 4 hash-checked relays, dropped keys, home rewrite, overrides),
    `install-cloud.bats` (fake systemctl/loginctl: reconcile, trust gate, legacy stop order, idempotence, dry run,
    rollback). `make test` 46/46.
  - Docs: cloud-rebuild (the one rebuild path), verify rows 3–3h, add/remove-repo, upgrade-claude-code,
    troubleshooting, sync-settings, 00-bootstrap, spec §2.4/§3.2 (pty decision), ADR 0002 implementation notes,
    CLAUDE.md real names, config/bin READMEs.
- **oci** (PR #3): bootstrap no longer installs Claude Code, writes `settings.json`, the PATH line, `agent@.service` or
  `fleet`. New step 5 removes the legacy setup idempotently and never touches `cc-*`. `/var/log/core/agent.log` kept
  (cc-orchestrator's rsyslog rule writes into it). `host/cloud/{agent@.service,fleet}` deleted, `wipe.sh` stops
  `cc-rc@*`/`cc-agents`, docs cross-referenced (CLAUDE.md, README, architecture, fleet-repos → pointer page,
  access-ssh, 00-first-deploy, wipe-and-restore, monitoring, troubleshooting), secrets-rotation: Tailscale secret is a
  non-expiring OAuth client secret, never rotated. `terraform fmt` of `compute.tf` (pre-existing).

## pty under systemd: not needed (evidence)
A transient unit with no terminal (`systemd-run --uid=agent -p StandardInput=null … claude remote-control --name
cloud/pty-probe --spawn worktree …` in `/data/fleet/offers-pipeline`, agent@ stopped) logged
`POST /v1/environments/bridge -> 200`, `✔ Ready · offers-pipeline`, and on SIGTERM
`[bridge:shutdown] Environment deregistered, bridge offline`. The live `cc-rc@offers-pipeline` runs the same way
(`Main PID … claude remote-control --name cloud/offers-pipeline …`, no tmux in its cgroup).
Side finding: the legacy `tmux kill-server` stop leaves the folder registered server-side for ~3–4 min
("This folder is already served by a terminal `claude remote-control` on this device"); `cc-rc@` retries every 30 s
and connected at 16:08:39 after the 16:05:38 cutover.

## Inventory on cloud
| | Before (15:29 UTC) | After (16:15 UTC) |
|---|---|---|
| units | `agent@.service` (oci), `agent@offers-pipeline` active+enabled | `cc-agents.service` active+enabled, `cc-rc@offers-pipeline` active+enabled; no `agent@*` |
| `/etc/systemd/system` | `agent@.service` | `cc-agents.service`, `cc-rc@.service` |
| `/usr/local/bin` | `fleet` (oci), `core-disk-metric`, `oci` | `core-disk-metric`, `oci` |
| `/opt/core` | `agent@.service`, `fleet` + machine files | machine files only |
| rsyslog | `30-core-agent.conf` (oci) | `30-cc-orchestrator.conf` (cc-orchestrator) |
| tmux | `-L agent-offers-pipeline` (session `main`) | default socket, session `fleet` (cc-agents) |
| cron | none for agent; `/etc/cron.d`: `e2scrub_all`, `sysstat` | unchanged (nothing Claude-related) |
| claude | 2.1.296 (oci bootstrap), not on non-interactive PATH | 2.1.301 (self-updated), PATH line in `.bashrc` |
| `~/.claude/settings.json` | `{ "permissions": { "defaultMode": "auto" } }` (oci) | synced from the Mac, 4 relays, prefix `cloud` |
| plugins | none | `claude-md-management`, `claude-hud` (via `--install-plugins`) |
| `/data/fleet` | `offers-pipeline` | + `arbinet`, `arbinet-specs`, `job-hunt`, `wick-sweep-reclaim` (GitHub clones) |
| worktrees | `offers-pipeline/.claude/worktrees/bridge-cse_01SUWQ…` (legacy RC, locked by a dead pid, no changes/commits/ignored files) | removed (+ its branch); transcripts in `~/.claude/projects` kept |
| trust | `/data/fleet/offers-pipeline`; `remoteDialogSeen: true`; logged in | unchanged (4 new repos + `/data/fleet` need trust: human) |
| linger | yes | yes |

## Verified
- `make lint` → `lint: ok (18 files)`; `make test` → 46/46 ok. oci: `make plan-core` → **No changes.**;
  `terraform fmt -check -recursive` ok; shellcheck ok.
- `./install.sh cloud --dry-run` (before migration): 26 `would …` lines (legacy stop/removal, units, clones,
  `would start cc-rc@offers-pipeline`), settings diff, `4 macOS-only hook handler(s) relayed`; nothing written.
- `./install.sh cloud` (live): 26 changes, `started cc-rc@offers-pipeline`, `4 … relayed`. Re-runs:
  `install.sh cloud-local: no changes`, `sync ok`, `settings ok`, `files ok`, `Mac side: 0 change(s)`.
  The second run first exposed a bug (`list-unit-files` exit 1 under `pipefail` once no `agent@` existed). Fixed, and
  the fake systemctl now reproduces it.
- Dispatch: `claude --bg -w p4b-hello` in `/data/fleet/offers-pipeline` → `.claude/worktrees/p4b-hello`, reply
  "hello from cloud", `/rc active`; `fleet` on the Mac listed `cloud done offers-pipeline hello from cloud`. Removed
  with `claude rm`.
- oci host-sync after install (from the PR branch), twice: 1st logged `legacy: removed /opt/core/agent@.service`,
  `/opt/core/fleet`, `/etc/rsyslog.d/30-core-agent.conf`; 2nd no `legacy:` lines. `cc-rc@offers-pipeline` MainPID
  4492 / NRestarts 2 / active since 16:08:39 and `cc-agents` MainPID 4205 since 16:05:44: identical before and after;
  unit files byte-identical to the repo. `install.sh cloud` afterwards: no changes.
- arbinet: cloned from GitHub; its gitignored `accounts.md` is not on cloud and was never copied.

## Outstanding (human)
1. Workspace trust on cloud: `/data/fleet` (Agent View: `ac` → "Yes, I trust this folder") and per repo
   `ssh -t cloud 'repo-init arbinet'` (also `arbinet-specs`, `job-hunt`, `wick-sweep-reclaim`) → accept → `/exit`;
   each starts its `cc-rc@`.
2. Claude app: check that device `cloud` lists `cloud/offers-pipeline` (and the others after 1); start a session → worktree.
3. Approved reboot: `ssh cloud 'sudo reboot'`, then verify.md 3d.
4. Optional live rollback drill (the classifier denied it here; bats covers it): `./install.sh cloud --rollback`,
   check `agent@offers-pipeline`, then `./install.sh cloud` (expect a ~3–4 min "already served" wait).
5. `~/Documents/arbinet` and `arbinet-specs` have local commits not on GitHub: the cloud clones lack them until pushed
   (then `ssh cloud 'git -C /data/fleet/<repo> pull --ff-only'`).
6. Cosmetic, optional: oci `terraform/core/observability.tf` strings ("agent@* unit events", "fleet ls") need
   `make apply-core`.
7. `repo-init` left `.gitignore`/`.worktreeinclude` edits uncommitted in the 5 cloud clones (by design): commit them
   in each repo via a PR when convenient.

## Post-merge (2026-10-16 16:18 UTC)
- Merged oci-infra-old#3 and cc-orchestrator#8; `git -C ~/Documents/{oci,cc-orchestrator} pull --ff-only`.
- From `~/Documents/cc-orchestrator` (main): `./install.sh mac` → 2 changes (links `cc-relay-hook`, `cc-sync-settings`);
  `./install.sh cloud` → `install.sh cloud-local: no changes` (rsync only refreshed mtimes); `make sync` →
  `settings ok`, `files ok`, `4 macOS-only hook handler(s) relayed`; `make test` 46/46;
  `cc-agents`, `cc-rc@offers-pipeline` active.
- The human items under "Outstanding" remain open.
