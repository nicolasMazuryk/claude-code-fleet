# Phase 6 — iPhone and Mac remote access

Date: 2026-10-16 · Branch: `phase-6-remote-access` (from `main` after PR #13) · Status: **scriptable part done;
blocked on the human (Remote Login)**.

## Done
- **`config/mac/sshd-100-keys-only.conf`**: pubkey only, no password / keyboard-interactive, no root, `AllowUsers
  nicolas`. It sorts before Apple's `100-macos.conf` (sshd keeps the first value).
- **`bin/mac-remote-access`** (Mac-only; skipped on cloud by `install.sh`):
  - `status`: read-only report on Remote Login, the drop-in, authorized key fingerprints, AC sleep and the mosh
    firewall rule. Exit 1 if anything is missing.
  - `add-key`: one validated public key, private keys refused, backup first, 0600, idempotent.
  - `selftest`: throwaway `from="127.0.0.1,::1"` key, ssh and mosh login to localhost, measures TCC and the Keychain,
    then removes the key.
  - `apply` (sudo, run by the human):
    - installs the drop-in. The backup goes to `/etc/ssh/`, **not** `sshd_config.d/`, which `sshd_config` includes
      with `*`. It runs `sshd -t` and rolls back on failure.
    - `pmset -c sleep 0 displaysleep 10`, and re-allows mosh-server in the firewall on a Cellar path change.
    - **lockout guard:** refuses unless a phone key is present and the self-test key login works (`--force`
      overrides).
- **`tests/mac-remote-access.bats`** (6): add-key appends once / backup / 0600; refuses private, garbage and multi-key
  input; apply's lockout guard; apply idempotence; backup outside the Include dir plus rollback on `sshd -t` failure;
  drop-in content.
- **Docs:** `docs/runbooks/iphone-setup.md` rewritten:
  - §A: the Mac side, in lockout-safe order
  - the Full Disk Access trade-off and a recommendation
  - §B: iPhone
  - §C: what a push tap opens
  - §D: verify
  `config/iphone/hosts.md` (new). Also updated: verify rows 7–7d and §10.6, mac-rebuild steps 7 and 9, spec §4.5 and
  §6, troubleshooting (5 rows), bootstrap row 11, bin/ and config/ READMEs.

## Findings
- **Mac state (2026-10-16):** Remote Login **off** (port 22 closed, no host keys yet), no `~/.ssh/authorized_keys`,
  AC `sleep 10` / `displaysleep 10`. The firewall already allows mosh-client and mosh-server at the current Cellar path
  `…/mosh/1.4.0_43/…` (Phase 2), so there is no duplicate entry. Only `100-macos.conf` is in `sshd_config.d/`.
- **ntfy Click:** `hooks/agent-push.sh` sets `Click: https://claude.ai/code/$CLAUDE_CODE_BRIDGE_SESSION_ID`. In
  Claude Code 2.1.301:
  - the CLI sets that variable in its own `process.env` when a REPL is bridged to Remote Control, so hooks inherit it,
    and removes it on disconnect
  - the value is the same compat id (`cse_…` → `session_…`) the CLI uses for its own session URL `<base>/code/<id>`
    (found in the binary), so the URL format is right
  - no push so far has carried a Click (`push.log`: 0 `(with Click)`): every push came from Agent View's
    `agent_*` notifications or the test, and Agent View background sessions are not bridged (this agent's own `--bg`
    session has no such variable, even with `remoteControlAtStartup: true`)
  - so: app-started and interactive sessions → deep link; Agent View sessions → the tap opens ntfy
  - whether iOS opens `claude.ai/code/session_…` in the Claude app or in Safari: human verify (row 7d)
- A live probe to show the variable's value inside an interactive cloud session was **stopped by the auto-mode
  classifier** (it would have shown a session id). The throwaway tmux session `p6probe` was killed;
  `/data/fleet/offers-pipeline` was left clean (`main`, no worktree).

## Verified (2026-10-16)
- `make lint` → `lint: ok (20 files)`; `make test` → 64/64 ok (58 before, +6).
- `bin/mac-remote-access status` →
  - `remote-login OFF`, `keys-only missing`, `authorized no key`
  - `sleep AC sleep 10, displaysleep 10`
  - `firewall ok mosh-server /opt/homebrew/Cellar/mosh/1.4.0_43/bin/mosh-server allowed`
  - rc 1
- `bin/mac-remote-access selftest` → `REMOTE_LOGIN=off`, rc 1; `authorized_keys` was left untouched.

## Not verified (blocked)
- Every phone verify (dispatch, peek-reply, attach-approve on both hosts; push tap), the self-test (TCC / Keychain,
  §10.6) and the Full Disk Access decision: all need Remote Login on first.

## Outstanding (human), in order
1. Remote Login on (System Settings → General → Sharing; only `nicolas`; "full disk access for remote users" off).
2. Then resume the agent: `mac-remote-access selftest` → FDA decision with data → Moshi key → `add-key` → Moshi `mac`
   with the key → `mac-remote-access apply` in a real terminal → phone verify (row 7, 7d).
