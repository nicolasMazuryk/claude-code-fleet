# iPhone setup (and the Mac side of phone access)

Status: Phase 6. Host table: [`config/iphone/hosts.md`](../../config/iphone/hosts.md). `[H]` = human-only (phone,
GUI, sudo). Idempotent: every step can be re-checked and re-run; `mac-remote-access status` shows what is missing on
the Mac side.

The phone reaches **cloud** with mosh over Tailscale SSH (no key), and the **Mac** with mosh over the Mac's own sshd
(Moshi key, keys only). The Claude app reaches both through Remote Control (outbound from each host, no tailnet
needed). ntfy pushes arrive only when you're away from the Mac ([architecture](../architecture.md)).

## A. Mac: let the phone in

`mac-remote-access` is in `~/.local/bin` after `./install.sh mac` (before the Phase 6 PR is merged, run it as
`bin/mac-remote-access` from the checkout). The steps follow the order below so you keep a working way in:
password logins stay on until a key login is proven.

1. `[H]` System Settings → General → Sharing → **Remote Login**: on; "Allow access for: Only these users" →
   `nicolas` only (remove Administrators); leave "Allow full disk access for remote users" **off** (see
   [Full Disk Access](#full-disk-access-for-remote-logins) below).
   Check: `mac-remote-access status` → `remote-login on`.
2. Self-test (no phone needed): `mac-remote-access selftest`. It adds a throwaway key restricted to
   `from="127.0.0.1,::1"`, logs in over ssh and mosh to `localhost`, removes the key again, and prints:
   `KEY_LOGIN`, `SSH_DOCUMENTS`, `TMUX_SESSIONS`, `TMUX_SERVER_DOCUMENTS`, `CLAUDE_LOGGED_IN`, `CLAUDE_KEYCHAIN`,
   `MOSH_DOCUMENTS`. Record the result in [verify.md](verify.md) §10.6.
3. `[H]` Phone: Moshi → Keys → generate an **Ed25519** key (on-device; Secure Enclave if offered). Share only the
   **public** key to the Mac (AirDrop/Notes/Universal Clipboard into a file, e.g. `~/Downloads/moshi.pub`).
4. `mac-remote-access add-key ~/Downloads/moshi.pub` (or `pbpaste | mac-remote-access add-key -`). It refuses
   private keys and anything that is not exactly one valid public key; backs up `~/.ssh/authorized_keys`; no-op if
   the key is already there. Then delete the copy in Downloads.
5. `[H]` Phone: Moshi host `mac` (table below) → connect. It must log in **with the key** (Moshi never asks for a
   password). This is the working path that the next step depends on.
6. `[H]` Real terminal on the Mac (sudo prompts; the `!` shell in Claude Code has no TTY):
   `mac-remote-access apply`. It refuses unless a phone key is in `authorized_keys` and the self-test key login works,
   then:
   - installs `config/mac/sshd-100-keys-only.conf` → `/etc/ssh/sshd_config.d/100-keys-only.conf` (keys only,
     `AllowUsers nicolas`, no root). Any older copy is backed up to `/etc/ssh/100-keys-only.conf.bak.<ts>`, **outside**
     `sshd_config.d/`, because `sshd_config` includes `sshd_config.d/*`. Runs `sudo sshd -t` and rolls back if it fails.
     macOS starts sshd per connection, so no restart is needed; open sessions stay up.
   - runs `pmset -c sleep 0 displaysleep 10`: on power the Mac never sleeps, the display still does. A closed lid
     still sleeps without an external display.
   - allows `$(realpath /opt/homebrew/bin/mosh-server)` in the Application Firewall if the Cellar path changed (it
     changes after `brew upgrade mosh`).
   A second run prints `mac-remote-access apply: no changes`. Check: `mac-remote-access status` (all ok, exit 0);
   from the phone, reconnect `mac`; from the Mac, `ssh -o PreferredAuthentications=password localhost` →
   `Permission denied (publickey)`.

### Full Disk Access for remote logins

macOS TCC blocks `~/Documents` for processes whose "responsible" app has no access. An ssh or mosh login on the Mac is
attributed to `/usr/libexec/sshd-keygen-wrapper`. The Remote Login checkbox "Allow full disk access for remote users"
grants the same thing.
- **Without it:** the login shell itself can't read `~/Documents`. So no `cd ~/Documents/<repo> && claude`, `git` or
  `ls` there from the phone shell, and a tmux server started *from* that login can't either.
- **But** `am` attaches to the `agents` session of the tmux server that the LaunchAgent started at login, and that
  server has Documents access (Phase 3). Agent View, dispatch, peek and attach then run inside that server, not in the
  ssh login. The same holds for any new window opened in that server.
- `selftest` measures exactly this: `SSH_DOCUMENTS` (the login itself) vs `TMUX_SERVER_DOCUMENTS` (the tmux server
  the phone attaches to).
- Granting it gives every key that can log in full read/write of the whole disk, including Mail, Messages and
  Keychain files. A leaked phone key would then expose everything, not just a shell.

Recommendation: leave it **off** when `TMUX_SERVER_DOCUMENTS=readable`. Work in the Mac through `am` (Agent View) or
`tmux new-window` inside that server. Grant it only if you need a plain shell in `~/Documents` from the phone; if you
do, grant `sshd-keygen-wrapper` and `$(realpath /opt/homebrew/bin/mosh-server)` in Privacy & Security → Full Disk
Access. If the tmux server isn't running (e.g. right after a crash), start it from the Mac, or with
`launchctl kickstart -k gui/$(id -u)/cc-orchestrator.claude.agents` from the phone.

## B. iPhone

1. `[H]` **Tailscale** (App Store) → sign in to the same tailnet (`tailnet-example`) → VPN on. Check: the app lists
   `macbook` and `cloud`. The phone is `autogroup:member`, so it may reach both; cloud can't reach the phone.
2. `[H]` **Moshi** (alternative: Blink Shell; same table). Settings: extra-keys row on (Esc, Ctrl, arrows, Tab).
   Add the two hosts from [`config/iphone/hosts.md`](../../config/iphone/hosts.md):
   - `cloud`: host `cloud`, user `agent`, **no key and no password** (Tailscale SSH authenticates the tailnet
     identity), mosh on, default mosh-server.
   - `mac`: host `macbook`, user `nicolas`, key = the Moshi key from A.3, mosh on, mosh-server
     `/opt/homebrew/bin/mosh-server` (a non-login ssh command doesn't have Homebrew on PATH).
   - Startup command, if Moshi offers it, else type a shortcut after connecting: **`am` on the Mac, `ac` on cloud**
     (both open that host's Agent View; on cloud `am` only prints a hint, since cloud never connects to the Mac).
   - Connection type: set **Mosh** explicitly (with the mosh-server path on `mac`). With *Auto*, Moshi falls back to
     SSH without saying why; an explicit Mosh shows the error instead.
3. `[H]` **ntfy** (App Store "ntfy", Philipp Heckel): already subscribed in Phase 5. If you re-add it, the topic is
   the content of `~/.config/agent-push/topic` on the Mac. Read it yourself, e.g. `pbcopy <
   ~/.config/agent-push/topic` and paste on the phone with Universal Clipboard. Never paste it into git, chat logs or
   an agent session. Server: default `ntfy.sh`.
4. `[H]` **Claude** app → same claude.ai account → Code tab lists `mac/<repo>` and `cloud/<repo>` (Phase 4b).
   iOS Settings → Notifications → Claude → **off** (ntfy is the one push channel; the hosts also have
   `agentPushNotifEnabled`/`inputNeededNotifEnabled` = false).
5. Optional `[H]`: claude.ai → Settings → **Require trusted devices** for Remote Control.

## C. What a push tap opens

`hooks/agent-push.sh` adds `Click: https://claude.ai/code/$CLAUDE_CODE_BRIDGE_SESSION_ID` when that variable is set
in the hook's environment. Claude Code 2.1.301 sets it in its own process (hooks inherit it) **only while that session
is bridged to Remote Control**. The value is the same compat id (`session_…`) the CLI uses to build its own session
URL (`<base>/code/<id>`). So:

| Push from | Click URL? | Tap opens |
|---|---|---|
| A session started from the Claude app (RC server `--spawn worktree`), or an interactive terminal `claude` with `remoteControlAtStartup` (its own `Stop` / `permission_prompt` hook) | yes | `claude.ai/code/session_…`: the Claude app if iOS hands the universal link to it, else Safari on claude.ai (same session, logged in) |
| An Agent View background session (pushed by Agent View's `agent_needs_input` / `agent_completed`, from the `claude agents` process) | no | the ntfy app (message shows host + repo text); open Moshi → `am` / `fleet` host |

Background sessions are not bridged: the variable is unset in this agent's own `--bg` session even with
`remoteControlAtStartup: true`. There is no per-session URL to link, so the "tap opens the session in the Claude app"
goal is reachable only for app-started or interactive sessions. `push.log` shows `pushed "…" (with Click)` when a
link was attached.

## D. Verify ([verify.md](verify.md) row 7)

From the phone, on **both** `cloud` and `mac`:
- **dispatch**: in Agent View, `@<repo> say hello` → a new row, a worktree under `<repo>/.claude/worktrees/`;
- **peek-reply**: select the row, peek (Space), type a reply, Enter → the session continues;
- **attach-approve**: `→` to attach to a session waiting on a permission prompt (ask it for something that needs
  one, e.g. a command outside the allowlist on the Mac), approve, `←` to detach;
- **push tap**: lock the Mac, start a session from the Claude app, let it finish → the push has a Click URL
  (`push.log` `(with Click)`), and the tap opens that session.
