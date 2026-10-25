# hooks/

Claude Code hook scripts.

| Script | What | Installed |
|---|---|---|
| `agent-push.sh` | Notification + Stop hook: ntfy push to the iPhone only when `agent-present` fails (you're away from the Mac). Logs each decision to `~/.local/state/agent-push/push.log` (no topic, no message) | Mac: copied to `~/.claude/hooks/` by `install.sh mac`; cloud: mirrored from the Mac by `cc-sync-settings` |
| `session-env.sh` | SessionStart hook (all sources: startup, resume, clear, compact, fork): appends `export CLAUDE_SESSION_ID=<session_id>` to `$CLAUDE_ENV_FILE` so every later Bash call has it. The id must match `[A-Za-z0-9-]+`, else nothing is written | Mac: copied to `~/.claude/hooks/` and registered by `install.sh mac`; cloud: script and settings entry mirrored by `cc-sync-settings` |

Gating table and log format: `tests/agent-push.bats`. Spec: `docs/spec.md` §2.7.
