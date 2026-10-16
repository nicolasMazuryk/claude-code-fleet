# Architecture

Adapted from `prompts/prompt.md` §1 for the real machines. Details and code: [spec.md](spec.md). Why: [decisions/](decisions/).

```
                     ┌──────────────────── iPhone ─────────────────────┐
                     │  Moshi (mosh)            ntfy        Claude app  │
                     └───┬───────────┬───────────▲─────────────▲───────┘
           mosh macbook  │           │mosh cloud │ push         │ Remote Control
     (sshd + mosh-server)│           │(TS SSH)   │ (away only)  │ (outbound-only via Anthropic)
            ┌────────────┘           │           │              │
            ▼                        ▼           │              │
┌──── MacBook (macbook, nicolas) ─┐  ┌──── cloud = core-vm-cloud (agent) ────┐
│ AGENTS_ROOT ~/Documents         │  │ AGENTS_ROOT /data/fleet               │
│ tmux "agents" → Agent View      │  │ tmux "fleet" → Agent View             │
│   (LaunchAgent …claude.agents)  │  │   (cc-agents.service)                 │
│ tmux "rc" → RC server per repo  │  │ cc-rc@<repo>.service per repo         │
│   in config/mac/repos.txt       │  │   in config/cloud/repos.txt           │
│ sessions in <repo>/.claude/     │  │ sessions in <repo>/.claude/           │
│   worktrees/<name>              │  │   worktrees/<name>                    │
│ hooks: 4× afplay choo-choo      │  │ hooks: same events/matchers; afplay → │
│        agent-push → ntfy ───────┼──┼──►    cc-relay-hook → events.jsonl   │
│                                 │  │        agent-push  → ntfy             │
│ agent-relay ══ one ssh ═════════┼═►│ events → Mac runs its own handler     │
│   (LaunchAgent …claude.relay)   │  │                                       │
│   presence up stdin (15 s) ═════┼═►│ mac-present marker → push gating      │
│ cc-sync-settings ═══════════════┼═►│ settings, CLAUDE.md, skills, hooks…   │
│ cmux · fleet ═══════════════════┼═►│ claude agents --json, systemctl       │
└─────────────────────────────────┘  └───────────────────────────────────────┘
  Tailscale (tailnet-example): members → *:* (+ internet via exit node static-ip) ; no rule with src tag:cloud → cloud can't reach Mac/iPhone.
  Existing exit node static-ip keeps working. Break-glass into cloud: OCI Bastion (oci repo, `make ssh VM=cloud`).
```

## Components and owners

| Component | Where | Owner |
|---|---|---|
| VM, `/data` volume, `agent` user, apt packages, Node, Tailscale daemon + `tailscale up`, mosh iptables rule, Vault secrets | cloud | `~/Documents/oci-free-tier-platform` (`host/cloud/bootstrap.sh`, `make host-sync VM=cloud`) |
| Claude Code binary, Agent View, RC servers (`cc-rc@`, `cc-agents`), hooks, settings, scripts in `bin/` | both | this repo (`install.sh`) |
| Tailnet policy | Tailscale admin console | this repo (`config/tailscale/policy.hujson`, applied by a human) |
| Mac Remote Login, Full Disk Access, firewall | Mac | this repo's runbooks (manual, human) |
| iPhone apps | iPhone | `docs/runbooks/iphone-setup.md` (manual) |

See [ADR 0002](decisions/0002-ownership-split.md).

## Data flows

### Dispatch
- **Terminal:** `@<repo> task` in Agent View (Mac pane `am`, cloud pane `ac`, or mosh from the phone). Agent View sees
  every git repo one level below `AGENTS_ROOT`. Each session moves into `<repo>/.claude/worktrees/<name>`;
  `.worktreeinclude` copies `.env` files in.
- **App:** Claude app → Code → `mac/<repo>` or `cloud/<repo>` (RC server, `--spawn worktree`). Only repos in the
  host's `repos.txt` have a server ([ADR 0003](decisions/0003-repos-allowlist.md)).

### Sound relay (cloud → Mac speaker, Mac-initiated)
1. `cc-sync-settings` replaces each of the 4 macOS-only `afplay` handlers in cloud's settings with
   `cc-relay-hook <event> <group> <handler> <sha256[:16]>`.
2. On cloud the hook appends `{event, group, handler, sum, payload}` to `~/.local/state/agent-events/events.jsonl`.
3. The Mac's `agent-relay` (LaunchAgent) holds **one** ssh connection to cloud, opened by the Mac. Down it comes
   `tail -F` of that file; for each event the relay looks the handler up in the **Mac's** `~/.claude/settings.json`,
   checks the hash, and runs the Mac's own command with the payload on stdin. A mismatch ("Mac hook changed, run
   cc-sync-settings"), a malformed line or an event older than 120 s is skipped and logged (`/tmp/agent-relay.log`).
   Cloud can only name a handler, never supply a command. Reconnects with backoff (5 → 60 s).
4. launchd can't read `~/Documents` (TCC), so the LaunchAgent runs copies of `agent-relay`/`agent-present` that
   `install.sh mac` keeps in `~/.local/libexec/cc-orchestrator/`.

### Presence and pushes
- `agent-present` on the Mac: screen unlocked **and** HID idle < 120 s (`ioreg`).
- `agent-relay` writes `present`/`away` up the same ssh connection every 15 s; cloud's end touches/removes
  `~/.local/state/agent-events/mac-present`, and cloud treats a marker younger than 45 s as "present". A stopped relay,
  a sleeping Mac or a broken link therefore means "away" (extra pushes, never missed ones).
- How soon cloud sees "away" (the Mac's own pushes use `agent-present` directly, so only the idle threshold applies):
  locked screen → at the next update, ≤ 15 s; unlocked but idle → 120 s idle + ≤ 15 s; Mac asleep, relay stopped
  or link down → marker goes stale, ≤ 45 s.
- `hooks/agent-push.sh` (both hosts) posts to `https://ntfy.sh/<topic>` only when not present (the URL goes to curl
  as a config on a file descriptor, so the topic never shows in `ps`). Each decision is one line in
  `~/.local/state/agent-push/push.log` (event, type, `job=set|unset`, result; never the topic or message). Topic: local file
  `~/.config/agent-push/topic`, backed up in Vault as `core-secret-ntfy-topic` ([ADR 0004](decisions/0004-ntfy-public-topic.md)).
- Native Claude app pushes are off (`agentPushNotifEnabled`/`inputNeededNotifEnabled: false`) so ntfy is the only channel.

### Settings
- Mac `~/.claude` → `config/claude/` via `cc-capture` (sanitized, reviewed as a git diff).
- `config/claude/` + `settings.orchestrator.json` → Mac via `install.sh mac` (deep-merge, backup first).
- Mac `~/.claude` → cloud via `cc-sync-settings` (home path rewrite, Mac-only bits dropped, `cloud-settings.json`
  merged on top). See [ADR 0005](decisions/0005-capture-apply-settings.md).

### Overview
`fleet` (Mac) merges `claude agents --json` from the Mac and from `ssh cloud`, waiting-for-you first; it also wraps
the old oci verbs: `fleet logs|restart|attach <host> <repo>`.

## Trust boundaries

- Cloud runs agents with `permissions.defaultMode=auto`, passwordless sudo and docker: treat it as untrusted relative
  to the Mac. Hence no `src: tag:cloud` ACL, no Mac keys on cloud, and the hash-checked relay.
- claude.ai login is the only credential for Remote Control on each host; it is never synced.
- The ntfy topic is the only shared secret on the push path; it is unguessable, not in git.
