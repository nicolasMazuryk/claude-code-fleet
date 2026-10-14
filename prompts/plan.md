# cc-orchestrator — phased implementation plan

## Context

`prompts/prompt.md` describes a three-device Claude Code orchestration: Agent View in tmux plus Remote Control servers on the MacBook and on cloud, reached from the iPhone by mosh or the Claude app. It also covers sound relay, presence-gated ntfy pushes, settings mirroring and a Tailscale ACL. The spec is generic (`~/Projects`, user `ubuntu`, `~/src`, fnm, a public-ish VM). The real machines differ, so the spec has to be adapted. This repo must also become the **single source of truth**: rebuilding the Mac, the OCI VM or the iPhone setup should be "follow this repo". Future Claude Code agents must be able to read the repo and safely extend it.

### Facts found (drive every adjustment)

| Area | Spec assumes | Reality |
|---|---|---|
| Mac repos root | `~/Projects` | `~/Documents` (32 git repos, no spaces; `FIO`, `fio.contracts`) |
| Mac node | fnm | nvm (`~/.nvm`, node v24.21.0), pnpm via corepack |
| Mac tools | tmux, mosh | **missing**; jq is `/usr/bin/jq`; cmux and Ghostty installed; gh, rsync in `/opt/homebrew` |
| Mac Tailscale node | `macbook` | currently `nicolas-macbook-pro` (tailnet `tailnet-example`) → **rename to `macbook`**; exit node `static-ip` must stay working |
| Mac Remote Login | on | **off** |
| Mac sound hooks | 1 Choo Choo hook | **4** `afplay ~/.claude/sounds/choo-choo.mp3` hooks: Stop (jq-guarded), Notification `permission_prompt\|elicitation_dialog`, PreToolUse `AskUserQuestion\|ExitPlanMode`, StopFailure |
| Mac settings | — | `agentPushNotifEnabled`/`inputNeededNotifEnabled` = true, no `remoteControlAtStartup`, no `~/.claude/CLAUDE.md`, statusline script hardcodes missing node v24.13.0 (bug), plugins `warp`, `claude-hud`, `claude-md-management` |
| Cloud host | `cloud`, user `ubuntu`, `~/src`, port 22 | `core-vm-app` (A1 2 OCPU/12 GB, Ubuntu 24.04 arm64, uk-london-1), **no public IP, Bastion-only**, agents run as user **`agent`** (home `/data/home/agent`, persistent 100 GB `/data` volume), repos in **`/data/fleet/<repo>`** |
| Cloud CC today | — | `~/Documents/oci` (`host/app/bootstrap.sh`) installs Claude Code, `agent@<repo>.service` (tmux + `claude remote-control --spawn worktree`), `/usr/local/bin/fleet` CLI, GitHub PAT from OCI Vault. No Tailscale, no mosh, no Agent View |
| OCI invariants | — | no public IP, no `0.0.0.0/0` ingress, secrets only in OCI Vault, free-tier block storage full (200/200 GB), host changes via `make host-sync VM=app` |
| claude CLI | — | 2.1.300; `claude agents --json`, `remote-control --spawn worktree --name --remote-control-session-name-prefix --[no-]create-session-in-dir --capacity` all exist |

### Decisions (confirmed with user)

1. **Cloud access = Tailscale on `core-vm-app`.** It is outbound-only, so the OCI no-ingress and no-public-IP invariants hold. The node is `cloud` with `tag:cloud`, and its auth key lives in OCI Vault. Bastion stays as break-glass.
2. **Ownership split.** The `oci` repo keeps the VM, disk, packages, the `agent` user, Tailscale, the mosh firewall rule and Vault secrets. **cc-orchestrator owns everything Claude Code**: scripts, Agent View, RC servers, hooks, settings sync and the cloud systemd units. `agent@.service` and `/usr/local/bin/fleet` are removed from the oci bootstrap and replaced by units installed from this repo.
3. **RC servers come from a versioned allowlist** (`config/<host>/repos.txt`). Agent View `@` dispatch still sees every repo under `AGENTS_ROOT`.
4. **ntfy.sh public**, with an unguessable topic. The topic is also stored in OCI Vault so a rebuild can recover it.

Defaults I'll assume unless told otherwise:
- This repo gets a **private** GitHub remote, `nicolasMazuryk/cc-orchestrator`.
- The Mac's Tailscale machine name becomes `macbook` (renamed in Phase 2 with `tailscale set --hostname=macbook` plus a rename in the admin console; MagicDNS `macbook.tailnet-example.ts.net`).
- The iPhone terminal app is Moshi; Blink is documented as an alternative.

## Target repo layout

```
CLAUDE.md                     # agent operating manual: invariants, layout, how to change things, verification
README.md                     # human entry point → docs/
docs/
  architecture.md             # adapted diagram + data flows (sound relay, presence, push, sync)
  spec.md                     # the adapted spec (prompts/prompt.md rewritten for real paths/hosts)
  decisions/NNNN-*.md         # ADRs: tailscale-on-oci, ownership split, repos allowlist, ntfy, capture/apply model
  runbooks/
    00-bootstrap-from-zero.md # order of operations for all three devices
    mac-rebuild.md  cloud-rebuild.md  iphone-setup.md
    add-repo.md  remove-repo.md  sync-settings.md  rotate-secrets.md
    upgrade-claude-code.md  troubleshooting.md  verify.md (= rollout + §10 checks)
bin/                          # shared + host scripts (symlinked into ~/.local/bin)
  agent-env agents-loop rc-serve rc-servers repo-init agent-present cc-relay-hook
  fleet cc-sync-settings agent-relay cc-capture cc-doctor
hooks/agent-push.sh
config/
  claude/CLAUDE.md                # global agent rules (source for ~/.claude/CLAUDE.md)
  claude/settings.mac.json        # captured, sanitized snapshot of Mac ~/.claude/settings.json
  claude/settings.orchestrator.json  # keys this repo enforces (merged on apply)
  claude/cloud-settings.json      # cloud-only overrides
  claude/statusline-combined.sh  claude/sounds/choo-choo.mp3
  mac/{config, repos.txt, tmux.conf, zshrc.snippet, ssh_config.snippet, cmux.json, sshd-100-keys-only.conf}
  mac/launchd/*.plist.tmpl
  cloud/{config, repos.txt}  cloud/systemd/{cc-agents.service, cc-rc@.service}
  tailscale/policy.hujson         # full tailnet policy as applied (incl. existing exit-node rules)
  iphone/hosts.md                 # Moshi host table, ntfy subscription, Claude app settings
install.sh                    # ./install.sh mac | cloud   (idempotent; cloud runs over ssh)
Makefile                      # install-mac, install-cloud, sync, capture, doctor, fleet, lint, test
tests/                        # shellcheck + bats: sync transform, relay hash check, agent-push gating
prompts/prompt.md             # original spec, kept verbatim as historical input
```

**Model for `~/.claude`: capture/apply, not symlinks.** Claude Code rewrites `settings.json` atomically, which would break a symlink.
- `cc-capture` snapshots the curated Mac `~/.claude` files into `config/claude/`, sanitized, and shows a diff.
- `install.sh mac` applies them back.
- `cc-sync-settings` keeps the spec's behaviour: Mac → cloud.

Scripts in `bin/` are symlinked, so editing the repo changes what runs. Secrets never enter git:
- the ntfy topic
- the Tailscale auth key
- claude.ai logins
- the GitHub PAT

## Spec adjustments to make (code-level)

- **`agent-env`:** source nvm on the Mac (`$NVM_DIR/nvm.sh`, default alias) instead of fnm. Cloud uses system node (NodeSource), so it loads no manager. Add `/data/home/agent/.local/bin` on Linux.
- **Configs:**
  - Mac: `AGENT_HOST=mac`, `AGENTS_ROOT=$HOME/Documents`, `AGENTS_SESSION=agents`, `REPOS_FILE=…/config/mac/repos.txt`.
  - Cloud: `AGENT_HOST=cloud`, `AGENTS_ROOT=/data/fleet`, `AGENTS_SESSION=fleet`.
- **`rc-servers`:** iterate over `repos.txt` instead of every dir.
  - Mac: tmux session `rc`, one window per repo.
  - Cloud: `systemctl enable --now cc-rc@<repo>` and disable units no longer listed.
  - `rc-serve` keeps the spec flags (`--name $AGENT_HOST/<repo> --spawn worktree --no-create-session-in-dir --remote-control-session-name-prefix $AGENT_HOST`).
- **Cloud services:**
  - `cc-rc@.service` is the successor of oci's `agent@.service`: `User=agent`, keeps `Restart=always` and `CPUWeight`, logs to journald.
  - `cc-agents.service` runs `agents-loop` in tmux session `fleet` as `agent` and replaces the spec's `@reboot` cron.
  - `loginctl enable-linger agent`.
- **`repo-init`:** on cloud, clone `https://github.com/nicolasMazuryk/<repo>.git` (as oci `fleet add` did) into `/data/fleet`. It also appends the repo to `repos.txt` when given `--rc`.
- **`fleet`:** ssh as `agent@cloud`. Rename oci's old `fleet` CLI's useful verbs (`logs`, `restart`, `attach`) into `fleet logs|restart|attach <host> <repo>` subcommands so nothing is lost.
- **Mac `~/.ssh/config`:** `Host cloud` → `HostName cloud`, `User agent`, ControlMaster, with keys handled by Tailscale SSH. The Tailscale ACL `ssh` rule allows users `agent` and `ubuntu`.
- **Hooks:** append `agent-push.sh` groups to `Notification` and `Stop` after the existing 4 sound groups. `cc-sync-settings` must relay **all 4** `afplay` handlers (expect "4 relayed").
  - The relayed PreToolUse/Stop handlers run on the Mac via `sh -c` with the payload. The Stop handler's jq guard then evaluates the cloud payload, which is correct.
- **`cc-sync-settings` additions:**
  - rewrite `/Users/nicolas` → `/data/home/agent`
  - drop or skip Mac-only `statusLine`, the `warp` plugin and `preferredNotifChannel`
  - copy `statusline-combined.sh` only if it is portable
  - reinstall missing plugins on cloud via `claude plugin install` (listed, not silently)
- **Orchestrator settings merged on the Mac:**
  - `remoteControlAtStartup: true`
  - `agentPushNotifEnabled: false`
  - `inputNeededNotifEnabled: false`
  - `env.CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX=mac`
- **`cloud-settings.json`:** `permissions.defaultMode=auto`, prefix `cloud`.
- **Fix the statusline node path:** use `$(command -v node)` or the nvm `current` alias.
- **macOS TCC gotcha.** launchd-started tmux, sshd and mosh-server processes touching `~/Documents` need Full Disk Access (or Documents access) for `/opt/homebrew/bin/tmux`, `sshd-keygen-wrapper` and `mosh-server`. Document this in mac-rebuild and check it in `cc-doctor`.
- **OCI Ubuntu iptables.** The image REJECTs most INPUT. Add `-i tailscale0 udp 60000:61000 ACCEPT` before the REJECT and persist it, in the oci bootstrap.

## Phases

Each phase ends with a commit on a feature branch (PR into `main`). oci-repo changes go through that repo's own branch/PR rules (`~/Documents/oci/CLAUDE.md`).

### Phase 0 — Repo foundation and docs skeleton
- Create `CLAUDE.md` (invariants: secrets never in git, Mac = settings source of truth, cloud reachable only via Tailscale/Bastion, cloud must never reach Mac, scripts idempotent, every change updates the matching runbook plus `verify.md`).
- Create the README, `docs/architecture.md`, the ADRs and `docs/spec.md` (the adapted spec).
- Create the directory skeleton, the Makefile, the `tests/` harness (shellcheck plus bats via brew) and `.gitignore`.
- Add the private GitHub remote.
- **Done when:** a fresh agent can answer "how do I add a repo to cloud?" from the docs alone.

### Phase 1 — Capture the current Mac state
- `cc-capture`: snapshot `~/.claude/settings.json` (sanitized, no tokens), the statusline script, the sounds, the `skills/` list and plugin list, plus the relevant `~/.zshrc` aliases, into `config/`.
- Commit it as the baseline, so the Mac can be rebuilt even before the later phases land.

### Phase 2 — Network: Tailscale on cloud (oci repo PR plus tailnet policy)
- **oci `host/app/bootstrap.sh`:**
  - install `tailscale` and `mosh`
  - `tailscale up --ssh --hostname cloud --advertise-tags=tag:cloud --authkey $(secret_get core-secret-tailscale-authkey)` (reusable and tagged, so a rebuilt VM rejoins under the same name)
  - add the persistent iptables rule for mosh on `tailscale0`
- **oci Vault:** add the secrets `core-secret-tailscale-authkey` and `core-secret-ntfy-topic` via `make secret-put`.
- **oci docs:** update its runbooks to point at cc-orchestrator for Claude Code.
- **`config/tailscale/policy.hujson`:**
  - add `tag:cloud`
  - members → `*:*`
  - no rules sourced from `tag:cloud`
  - ssh rule members → `tag:cloud` as `agent`, `ubuntu`
  - **merge with existing rules** (static-ip exit node)
  - applied in the admin console before `tailscale up`
- Rename the Mac's Tailscale node to `macbook` (admin console → machine → Edit name, or `tailscale set --hostname=macbook`). Record it in `config/tailscale/policy.hujson` comments and in `mac-rebuild.md`.
- Apply with `make host-sync VM=app`.
- **Verify:**
  - `ssh cloud true` and `mosh cloud` work from the Mac
  - `tailscale ping macbook` from cloud fails at the ACL
  - Bastion `make ssh VM=app` still works

### Phase 3 — Mac runtime
- `brew install tmux mosh shellcheck bats-core`
- `./install.sh mac` (idempotent):
  - symlinks `bin/*` into `~/.local/bin`
  - writes `~/.config/cc-orchestrator/config`
  - installs `~/.tmux.conf` and `~/.claude/CLAUDE.md`
  - deep-merges `settings.orchestrator.json` into settings, with a backup first
  - appends the agent-push hook groups idempotently
  - creates the ntfy topic (or fetches it from Vault via `oci secrets`)
  - renders and bootstraps the two LaunchAgents (`cc-orchestrator.claude.agents`, `.relay`) with real paths
  - adds the zsh snippet (`am`, `ac`, `fleet`; keeps the existing `c`, `ca`, `cw`, `cbg`)
  - writes `~/.config/cmux/cmux.json`
  - fixes the statusline
- Accept Remote Control once, then run `repo-init` for the allowlisted repos.
- **Grant Full Disk Access** to tmux (manual step, documented).
- **Verify:**
  - `am` shows Agent View
  - `@<repo> hello` creates a worktree with `.env`
  - the `rc` tmux session has one window per allowlisted repo
  - the Claude app lists `mac/<repo>`
  - `fleet` shows Mac sessions

### Phase 4 — Cloud runtime (cc-orchestrator takes over from oci)
- **oci PR:** remove `agent@.service`, `fleet` and the `claude settings.json` write from `bootstrap.sh`. Keep the Claude Code binary install, or move it here too; recommendation: move it here for a single owner.
- **`./install.sh cloud`** (run from the Mac):
  - rsyncs the repo to `/data/home/agent/cc-orchestrator`
  - symlinks `bin/`
  - writes the cloud config
  - installs the `cc-agents` and `cc-rc@` units
  - migrates by stopping and disabling `agent@*` and enabling `cc-rc@<repo>` for each repo in `config/cloud/repos.txt`
  - installs the tmux conf and the ntfy topic
  - runs `cc-sync-settings`
- One-time manual steps, all in the runbook:
  - `sudo -iu agent claude auth login` if not already logged in; it persists on `/data`
  - accept Remote Control once
  - accept workspace trust per repo via `repo-init`
- **Verify:**
  - `ac` attaches to cloud Agent View
  - `@repo hello` lands in a worktree
  - the app lists `cloud/<repo>`
  - `fleet` shows both hosts
  - `cc-sync-settings` reports 4 relayed handlers
  - a VM reboot brings everything back

### Phase 5 — Sounds, presence and pushes
- The `agent-relay` LaunchAgent runs on the Mac. `agent-present` uses `ioreg` on the Mac and the marker file on cloud.
- `agent-push.sh` is on both hosts.
- Log `env` once to confirm that `CLAUDE_JOB_DIR` is passed to hooks (spec §10.3).
- **Verify:**
  - a cloud session question plays Choo Choo on the Mac
  - locking the Mac makes pushes arrive from both hosts within 30 s
  - an active Mac gets no pushes
  - a changed Mac hook makes the relay skip and log it

### Phase 6 — iPhone and Mac remote access
- Mac:
  - Remote Login for user `nicolas` only, with `sshd_config.d/100-keys-only.conf`
  - add the Moshi public key
  - allow mosh-server through the firewall
  - `pmset -c sleep 0 displaysleep 10`
  - Full Disk Access for sshd-keygen-wrapper and mosh-server
- iPhone:
  - Tailscale
  - Moshi hosts `cloud` (user `agent`, Tailscale SSH) and `mac` (`macbook`, `/opt/homebrew/bin/mosh-server`)
  - ntfy subscription
  - Claude app, with its own notifications off
- Optionally turn on **Require trusted devices** on claude.ai.
- Write `docs/runbooks/iphone-setup.md` as a step-by-step checklist with screenshots optional.
- **Verify:**
  - from the phone you can dispatch, peek-reply and attach-approve on both hosts
  - tapping an ntfy push opens the session in the Claude app

### Phase 7 — Hardening and disaster-recovery drills
- **`cc-doctor`:** a per-host health check covering:
  - tools and versions
  - config present
  - units and LaunchAgents running
  - RC windows match `repos.txt`
  - relay alive
  - ntfy topic present
  - settings drift (Mac vs `config/claude` vs cloud)
  - Full Disk Access
  - disk use of `/data` and the worktrees
- **Tests:** shellcheck on everything. bats tests for the `cc-sync-settings` transform (fixture `settings.json` → expected cloud JSON with 4 relays), the relay hash rejection, and the `agent-push` gating table.
- **Drills, recorded in `docs/runbooks`:**
  - **cloud:** oci `make wipe` → `make restore` → `install.sh cloud` → `cc-doctor` green
  - **Mac:** a fresh macOS user account, or a dry run of the `mac-rebuild` runbook
  - **iPhone:** delete and re-add the hosts
- Record the spec §10 findings in `docs/verify.md`.

## Critical files touched outside this repo
- `~/Documents/oci/host/app/bootstrap.sh`, `host/app/agent@.service` (removed), `host/app/fleet` (removed), oci `docs/runbooks/fleet-repos.md` and `access-ssh.md`, and oci `CLAUDE.md` (pointer to cc-orchestrator).
- Mac: `~/.claude/settings.json` (merged, backed up first), `~/.ssh/config` (appended `Host cloud`), `~/.zshrc` (snippet sourced), `~/Library/LaunchAgents/cc-orchestrator.*.plist`, `/etc/ssh/sshd_config.d/100-keys-only.conf`.

## Verification (end-to-end)
`docs/runbooks/verify.md` reproduces the spec's §9 rollout table with the real names. Each phase's "Verify" items are run and their output is noted in the PR. Final acceptance:
- `make doctor` is green on both hosts
- `make test` passes
- the cloud wipe/restore drill rebuilds a working cloud from `oci` + `cc-orchestrator` alone
