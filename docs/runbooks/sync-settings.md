# Change Claude Code settings (Mac = source of truth)

Status: Phase 1 (`cc-capture`), Phase 3 (apply), Phase 4 (`cc-sync-settings`).
Model: [ADR 0005](../decisions/0005-capture-apply-settings.md).

1. Change settings on the Mac (`/config`, edit `~/.claude/settings.json`, add a skill, …).
2. `make capture` (= `bin/cc-capture`) snapshots into `config/claude/` and `config/mac/zshrc.captured`
   (what is captured: [config/README.md](../../config/README.md)). Review `git diff`, commit on a branch, PR.
   - Sanitized: credential-like `env` keys (`TOKEN`, `KEY`, `SECRET`, `PASSWORD`, `AUTH`, `CREDENTIAL`) and
     `agent-push.sh` handlers are dropped from settings (and `~/.claude/hooks/agent-push.sh` is not copied: `install.sh` installs it from `hooks/`), and credential-like assignments in the zsh blocks are redacted.
     If anything still matches a secret pattern, it aborts and writes nothing. Remove the secret on the Mac (move it
     to Vault or a local file) and re-run.
   - Idempotent: an unchanged Mac prints `cc-capture: no changes`.
   - `bin/cc-capture --check` writes nothing and exits 1 on drift (used by `cc-doctor` in Phase 7).
3. `make sync` (= `cc-sync-settings`) — mirrors to cloud. Must print **`4 macOS-only hook handler(s) relayed`**.
   - Fewer than 4: a sound hook changed or uses a tool outside `CC_MAC_ONLY`; fix before relying on cloud sounds.
   - It lists plugins enabled on the Mac but missing on cloud with the `claude plugin install` command to run.
4. Keys this repo enforces live in `config/claude/settings.orchestrator.json` (Mac) and
   `config/claude/cloud-settings.json` (cloud). Change them there, then `./install.sh mac` / `make sync`.
5. Never edit cloud's `~/.claude` directly; the next sync overwrites it.

Until `make sync` is run, cloud sounds whose Mac handler changed are skipped and logged in `/tmp/agent-relay.log`.
