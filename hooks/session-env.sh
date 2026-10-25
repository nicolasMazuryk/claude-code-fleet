#!/usr/bin/env bash
# session-env.sh — SessionStart hook: export CLAUDE_SESSION_ID (the payload's session_id) into every later Bash call.
# Claude Code provides no session-id env var to Bash; browser-router's route/lease/shield read CLAUDE_SESSION_ID.
# Fires for every source (startup, resume, clear, compact, fork), so the id follows the session. Never blocks a session.
# Bash 3.2 safe; no jq needed.
set -u
payload=$(cat)
[ -n "${CLAUDE_ENV_FILE:-}" ] || exit 0
id=$(printf '%s' "$payload" | tr -d '\n' | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
case $id in ''|*[!A-Za-z0-9-]*) exit 0 ;; esac
printf 'export CLAUDE_SESSION_ID=%s\n' "$id" >> "$CLAUDE_ENV_FILE"
exit 0
