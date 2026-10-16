# Phase 5 — Sounds, presence and pushes

Date: 2026-10-16 · Branch: `phase-5-sounds-presence-pushes` (from `main` after PR #11)

## Done
- **`bin/agent-relay`** (Mac, LaunchAgent `cc-orchestrator.claude.relay`). It holds one ssh connection to cloud,
  opened by the Mac (`ControlMaster=no`, `ControlPath=none`, ServerAlive 15×2):
  - presence goes **up** stdin every 30 s; cloud's end touches/removes `mac-present`
  - `tail -F events.jsonl` comes **down** stdout
  - each event is validated (event `^[A-Za-z]+$`, numeric group/handler/ts, 16-hex sum) and must be ≤ 120 s old
  - the event is looked up in the Mac's `~/.claude/settings.json` and hash-checked, then runs the Mac's own command
    with the payload on stdin
  - otherwise the event is skipped and logged
  - reconnects use 5 → 60 s backoff
  - when the link goes, cloud's `tail` dies with it (stdin EOF + HUP/TERM trap)
- **TCC:** launchd still can't read `~/Documents`. A `launchctl submit` probe of `~/.local/bin/agent-present` gave
  `Operation not permitted`. So `install.sh mac` (new step `relay`) copies `agent-relay` and `agent-present` to
  `~/.local/libexec/cc-orchestrator/`; the plist runs the copy, and the relay is re-bootstrapped when a copy changes.
  No Full Disk Access is needed. On cloud, `agent-relay` is not linked (Mac-only).
- **`bin/agent-present`:** the marker age now uses `stat -c %Y || stat -f %m`, and `AGENT_PRESENT_OS` is a switch
  for tests.
- **`hooks/agent-push.sh`:**
  - one decision line per hook in `~/.local/state/agent-push/push.log`, capped at 256 KB. It has event, type,
    `job=set|unset` (`CLAUDE_JOB_DIR`) and the result, never the topic or the message.
  - the ntfy URL is passed as `curl -K <(…)`, so the **topic is no longer in argv** (it was, since Phase 3).
- **Tests:**
  - `tests/agent-relay.bats` (7): hash match runs the handler with the payload; a changed Mac hook is skipped and
    logged; wrong hash, position or another handler is skipped; malformed or injected fields are ignored and a
    cloud-sent `command` never runs; stale events are dropped; cloud `agent-present` marker age; an end-to-end run
    through a fake `ssh cloud` (cc-relay-hook → relay → handler; marker up and down).
  - `agent-push.bats` +4: decision log, topic not in argv, real curl against a local ntfy stand-in, curl failure.
  - `install-mac.bats`: libexec copies and plist path.
- **Docs:** architecture (sound relay, presence and pushes), spec §2.7, §4.3, §4.4; mac-rebuild; troubleshooting
  (relay and push.log rows); iphone-setup step 4 (ntfy subscription); verify rows 4–5c and §10 rows 3–4; bin/ and
  hooks/ READMEs; install.sh header.

## Verified (live, 2026-10-16)
- `make lint` → `lint: ok (19 files)`. `make test` → 58/58 ok (47 before this phase, +11).
- `./install.sh mac` from the worktree made 19 changes: relinks, the libexec copies, the relay plist and
  `bootstrapped cc-orchestrator.claude.relay`. A re-run printed `install.sh mac: no changes`, and the relay pid was
  unchanged (18058 → 18058).
- `./install.sh cloud`:
  - `cloud-local: no changes`; `files <f.st hooks/agent-push.sh` (the new hook mirrored)
  - `4 macOS-only hook handler(s) relayed`
  - cloud's `~/.claude/hooks/agent-push.sh` equals the repo's, and there is no `agent-relay` link on cloud
- Relay log, in order:
  - `starting`, `presence: away` (the human had been idle 160 s; the same reading came from my shell and from a
    `launchctl submit` probe), `connected to cloud, waiting for events`
  - later `presence: present`, after which the marker was refreshed and cloud `agent-present` agreed
- Injected on cloud:
  - `cc-relay-hook Notification 0 0 a3c139ab1f7bb302` → `ran Notification/0/0`, and `afplay
    /Users/nicolas/.claude/sounds/choo-choo.mp3` was seen running
  - stale hash `0000…` → `skipped …: the Mac's hook changed since the last sync, run cc-sync-settings`
  - a raw `{"event":"Stop;id",…,"command":"id"}` → `ignored malformed event`
- **Changed Mac hook** (`settings.json` backed up to `.bak.20261016-191027`, Notification command edited, then
  restored byte-identical):
  - while edited: `skipped Notification/0/0: the Mac's hook changed …`
  - after the restore: `ran Notification/0/0`
- **Real cloud session:** `claude --bg -w p5-relay` in `/data/fleet/offers-pipeline` replied "hello from cloud phase
  5".
  - relay log: `ran Stop/0/0 (cloud session 5fed7453)`
  - cloud `push.log`: `Stop:- job=set present: no push` and `Notification:agent_completed job=unset present: no push`
  - the session was removed with `claude rm`; its worktree is gone
- **Gating on cloud** (fake curl): fresh marker → `present: no push`; marker 2 min old → `pushed "done"`.
- **Real ntfy:** one labelled test push per host ("cc-orchestrator Phase 5 test push (ignore)", presence forced away)
  → `pushed "done"` on the Mac and on cloud (curl `-f` succeeded).
  - On the Mac the first attempt logged `job=set background session: no push`, because this agent's own shell is a
    background session. That is correct gating; the retry used `env -u CLAUDE_JOB_DIR`.
- **Reconnect:** cloud's end was killed → `connection to cloud ended; retrying in 5s` → `connected to cloud`. Exactly
  one `tail -n0 -F` remained on cloud.

## Findings
- **Spec §10.3:** `CLAUDE_JOB_DIR` **is** passed to hooks of `claude --bg` sessions. Agent View's
  `agent_completed`/`agent_needs_input` notifications come without it. The gating therefore pushes exactly once per
  background-session event.
- The lock check (`CGSSessionScreenIsLocked`) appears in `ioreg` only while locked; it could not be exercised without
  locking the human's screen. HID idle > 120 s covers locking anyway, just later (up to 120 s + 30 s beacon).

## Outstanding (human)
1. Hear it: trigger a question in a cloud session (e.g. `ac` → `@offers-pipeline` "ask me a yes/no question with
   AskUserQuestion") → Choo Choo on the Mac.
2. Subscribe the iPhone ntfy app to the topic (read it yourself from `~/.config/agent-push/topic`), then lock the Mac
   and confirm pushes from both hosts arrive within 30 s; unlocked and active → none. The two labelled Phase 5 test
   pushes sit in ntfy.sh's ~12 h cache and may show up right after subscribing; that is expected.

## Human verification (2026-10-16 ~19:25–19:32 local)
- Sound: the human heard Choo Choo for a cloud session's question; `/tmp/agent-relay.log`:
  `ran PreToolUse/0/0 (cloud session e875e110)`, `ran Notification/0/0 (cloud session e875e110)`.
- iPhone: subscribed to the topic in ntfy; both labelled test pushes arrived. With the Mac locked, pushes arrived from
  both hosts: `✅ cloud · done — sleep-wait-60-seconds finished` and `⚠️ mac · needs input — …`.
- Follow-up (human request): presence update every 15 s (was 30 s); cloud's freshness window scaled to 45 s (was 90 s).
