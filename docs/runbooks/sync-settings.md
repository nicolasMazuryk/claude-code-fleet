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
     `make sync ARGS=--install-plugins` runs them, adding the Mac's marketplace on cloud first: a GitHub repo, or a
     `directory` marketplace at the same path under cloud `$HOME` (clone that repo on cloud first, under `~/code/<repo>`).
     browser-router is the exception: `install.sh cloud-local` installs its plugin from `~/.local/share/browser-router`,
     and `cloud-settings.json` sets `extraKnownMarketplaces.browser-router` to that path.
   - Dropped on the way: `statusLine` (needs ccstatusline + claude-hud, Mac only), `preferredNotifChannel`,
     credential-like `env` keys, and everything `config/claude/mac-only.json` lists. `/Users/nicolas` becomes
     `/data/home/agent`.
   - `config/claude/mac-only.json` `plugins`: Mac-only plugins by name (`warp`, `mac-control-router`,
     `phone-control-router`: the iPhone is driven only from the MacBook, and cloud agents never use it). Their
     `enabledPlugins` entry, their `extraKnownMarketplaces` entry (unless a synced plugin shares it) and every
     `mcp__plugin_<name>_*` permission rule are dropped, so they are never listed as missing on cloud.
     `permissions`: exact rules dropped from every permission list. `permissionFiles`: settings files, relative to
     `$AGENTS_ROOT`, whose every permission rule is dropped too; `mac-control-router/setup/user-settings.json` is the
     single source of the plugin's rules (the macOS automation allows such as `Bash(osascript *)` and the Mac safety
     denies such as `Bash(sudo *)`, which would break cloud's sudo workflows). A listed file that is missing fails the
     sync. A new Mac-only plugin, rule or rule file goes there.
   - Mirrored with `rsync --delete`: `CLAUDE.md keybindings.json skills agents commands output-styles hooks profile`
     (symlinks copied as files; `skills/synced` is claude.ai's own). The previous cloud `settings.json` is kept as
     `settings.json.bak.<ts>`; nothing is written when it is unchanged.
   - `make sync ARGS=--dry-run` shows the diff and the rsync list without writing; `--print` prints the cloud `settings.json`.
4. Keys this repo enforces live in `config/claude/settings.orchestrator.json` (Mac) and
   `config/claude/cloud-settings.json` (cloud). Change them there, then `./install.sh mac` / `make sync`.
5. Never edit cloud's `~/.claude` directly; the next sync overwrites it.
6. Permission-stall settings (`PermissionDenied` hook, narrow allows):
   - `Bash(open -g x-apple.systempreferences:*)` is Mac-only (a mac-control-router rule, via `mac-only.json` `permissionFiles`).
   - `config/claude/hooks/permission-retry` (the `PermissionDenied` hook) runs unrelayed and returns `retry:true` only for
     read-only GUI probes: `peekaboo see|list|window list|menu list`, `defaults read`, `lsappinfo` read subcommands,
     `mdfind`, and the Peekaboo MCP `see` and `window`/`menu` with `action: list`. Anything else, any chained or
     redirected command and any parse error prints nothing (default silent). Those probes are already allowed by
     `Bash(peekaboo *)`, `Bash(lsappinfo *)`, `Bash(mdfind *)` and `Bash(defaults read *)`; the hook matters only for
     classifier-denied variants. On cloud it is a harmless no-op. Keep `afplay|osascript|terminal-notifier|say` out of
     its text, or `cc-sync-settings` turns it into an async relay stub that cannot return `retry`.
   - `Bash(osascript *)` stays allowed. Check `/permissions` to see whether it survives auto mode. The narrow
     alternative, not applied: replace it with `Bash(osascript -e *)` and `Bash(osascript -l JavaScript -e *)`.
   - browser-guard is not in `settings.json`: the browser-router plugin registers it (its `hooks/hooks.json`), with
     `onFailure:"block"` on its one PreToolUse entry (Chrome, computer-use, Peekaboo, Bash; Claude Code ≥ 2.1.295): a
     guard that cannot start, times out or exits other than 0/2 blocks the call instead of letting it through.
     browser-guard is a POSIX `sh` launcher that finds `node` itself (PATH, nvm, Homebrew, `/usr/local`) and exits 2
     when none exists, so it also starts under a minimal PATH (LaunchAgent, Remote Control). Not set on the
     PostToolUse/Stop entries (no effect or not a gate). `install.sh mac` strips any browser-guard handler left in
     `settings.json`, so `settings.json` carries no `onFailure` field.
   - `config/claude/hooks/permission-away` (the `PermissionRequest` hook, both hosts) keeps unattended sessions moving:
     while `agent-present` fails it denies every permission prompt with "Human away: approval needed for <tool> …
     list it under needs-approval", logs to `~/.local/state/agent-push/permission-away.log` and pushes a needs-input
     notification through `agent-push.sh`; while you are present it prints nothing and the normal prompt shows. Any
     error prints nothing (fail-open to the prompt). Claude Code runs PermissionRequest hooks only when it is about to
     prompt or would auto-deny a call that cannot prompt, so allowed calls never reach it.
   - mac-control-router GUI work runs unprompted: `permissions.allow` lists `open -a|-ga`, `open
     x-apple.systempreferences:*`, `killall Dock|Finder|SystemUIServer|ControlCenter`, `defaults write com.apple.dock *`
     and `cliclick` (Mac-only), and an `autoMode.allow` line names the GUI automation the guard already polices.
     `cc-sync-settings` drops every `autoMode.allow` line that names a Mac-only plugin, so cloud never gets it.
   - The SIP/FileVault deny floor lists only mutation forms (`csrutil disable|clear|enable`, `nvram -c|-d|*=*`,
     `fdesetup enable|disable|changerecovery|removerecovery`), so the status reads the mac-control-router guard allows
     (`csrutil status`, `nvram -p`, `fdesetup status`) are reachable; `tccutil reset` is asked by the guard. Repository
     visibility is not restricted, and merging the owner's own PRs is allowed at any time.
   - Auto-mode deletion scope: `autoMode.allow` lets the classifier delete anything under `~/**` (`rm`, `rm -rf`,
     `rmdir`, `unlink`, `trash`, `find -delete`), and `autoMode.environment` declares `~` the user's own single-user data
     (`/Users/nicolas` on the Mac, `/data/home/agent` on cloud). Still confirmed: `~` itself or all its top-level
     contents, `~/.ssh`, `~/.gnupg`, `~/Library/Keychains`, `~/.claude/settings.json`, `~/.claude.json`. On the Mac the
     mac-control-router PreToolUse guard separately rejects `rm -rf`/`rm -f` and points to `trash <path>` (recoverable);
     plain `rm` and `trash` pass. Cloud gets the rules with the next `make sync`. Mac-only autoMode rules (the
     mac-control-router GUI allow) are listed verbatim under `autoMode` in `config/claude/mac-only.json` and dropped
     from cloud's copy; edit that list whenever the live rule's text changes.
6. The global profile (`~/.claude/profile/*.md`: who the owner is, goals, working style, environments) and the
   project memories (`~/.claude/projects/<dir>/memory/`) are edited on the Mac in place. `make capture` saves them
   to `config/claude/profile/` and `config/claude/memory/<dir>/` in **plaintext in this public repo**
   ([ADR 0006](../decisions/0006-global-profile-and-memory-in-git.md)): never put a secret there. `make sync` mirrors the
   profile to cloud (verify row 3j); `install.sh mac` restores missing profile files and memory folders.

Until `make sync` is run, cloud sounds whose Mac handler changed are skipped and logged in `/tmp/agent-relay.log`.
