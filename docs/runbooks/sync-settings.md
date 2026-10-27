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
   - `bin/cc-capture --check` writes nothing and exits 1 on drift (`cc-doctor` reports it as a `settings` warning).
3. `make sync` (= `cc-sync-settings`) — mirrors to cloud. Must print **`4 macOS-only hook handler(s) relayed`**.
   - Fewer than 4: a sound hook changed or uses a tool outside `CC_MAC_ONLY`; fix before relying on cloud sounds.
   - It lists plugins enabled on the Mac but missing on cloud with the `claude plugin install` command to run;
     `bin/cc-sync-settings --install-plugins` runs them (adding the Mac's GitHub marketplace on cloud first).
   - Dropped on the way: `statusLine` (needs ccstatusline + claude-hud, Mac only), `preferredNotifChannel`,
     credential-like `env` keys, and everything `config/claude/mac-only.json` lists. `/Users/nicolas` becomes
     `/data/home/agent`.
   - `config/claude/mac-only.json` `plugins`: Mac-only plugins by name (`warp`, `mac-control-router`). Their
     `enabledPlugins` entry, their `extraKnownMarketplaces` entry (unless a synced plugin shares it) and every
     `mcp__plugin_<name>_*` permission rule are dropped, so they are never listed as missing on cloud.
     `permissions`: exact rules dropped from every permission list (the macOS automation allows such as
     `Bash(osascript *)` and the Mac safety denies such as `Bash(sudo *)`, which would break cloud's sudo workflows).
     A new Mac-only plugin or rule goes there.
   - Mirrored with `rsync --delete`: `CLAUDE.md keybindings.json skills agents commands output-styles hooks profile`
     (symlinks copied as files; `skills/synced` is claude.ai's own). The previous cloud `settings.json` is kept as
     `settings.json.bak.<ts>`; nothing is written when it is unchanged.
   - `--dry-run` shows the diff and the rsync list without writing; `--print` prints the cloud `settings.json`.
4. Keys this repo enforces live in `config/claude/settings.orchestrator.json` (Mac) and
   `config/claude/cloud-settings.json` (cloud). Change them there, then `./install.sh mac` / `make sync`.
5. Never edit cloud's `~/.claude` directly; the next sync overwrites it.
6. The global profile (`~/.claude/profile/*.md`: who the owner is, goals, working style, environments) and the
   project memories (`~/.claude/projects/<dir>/memory/`) are edited on the Mac in place. `make capture` saves them
   to `config/claude/profile/` and `config/claude/memory/<dir>/` in **plaintext in this public repo**
   ([ADR 0006](../decisions/0006-global-profile-and-memory-in-git.md)): never put a secret there. `make sync` mirrors the
   profile to cloud (verify row 3j); `install.sh mac` restores missing profile files and memory folders.

Until `make sync` is run, cloud sounds whose Mac handler changed are skipped and logged in `/tmp/agent-relay.log`.
