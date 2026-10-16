#!/usr/bin/env bash
# agent-push.sh — Claude Code hook (Notification + Stop): push to the iPhone via ntfy only when you're away from the
# MacBook (agent-present fails). Same file on both hosts; installed to ~/.claude/hooks/agent-push.sh by install.sh.
# Topic: ~/.config/agent-push/topic (0600, never in git). Exits 0 always so it can never block a session.
# Every decision is one line in ~/.local/state/agent-push/push.log (event, type, CLAUDE_JOB_DIR set or not, result;
# never the topic or the message), kept under 256 KB.
# Test hooks: AGENT_PRESENT (command, default ~/.local/bin/agent-present), NTFY_SERVER, AGENT_PUSH_CURL,
# AGENT_PUSH_LOG.
# shellcheck disable=SC1091
. "$HOME/.config/cc-orchestrator/config" 2>/dev/null
p=$(cat)
j() { jq -r "$1 // empty" <<<"$p" 2>/dev/null; }
ev=$(j .hook_event_name); t=$(j .notification_type)
L=${AGENT_PUSH_LOG:-$HOME/.local/state/agent-push/push.log}
log() {
  mkdir -p "$(dirname "$L")" 2>/dev/null || return 0
  [ -f "$L" ] && [ "$(wc -c < "$L")" -gt 262144 ] && : > "$L"
  echo "$(date '+%F %T') ${ev:--}:${t:--} job=$([ -n "${CLAUDE_JOB_DIR:-}" ] && echo set || echo unset) $*" >> "$L" 2>/dev/null
}
if ${AGENT_PRESENT:-"$HOME/.local/bin/agent-present"}; then log "present: no push"; exit 0; fi   # sounds are enough
topic=$(cat "$HOME/.config/agent-push/topic" 2>/dev/null) || { log "no topic file: no push"; exit 0; }
[ -n "$topic" ] || { log "empty topic: no push"; exit 0; }
[ -n "$(j .agent_id)" ] && { log "subagent: no push"; exit 0; }
case "$ev:$t" in
  Notification:agent_needs_input) kind="needs input" ;;           # Agent View, for any background session
  Notification:agent_completed)   kind="done" ;;
  *) [ -n "${CLAUDE_JOB_DIR:-}" ] && { log "background session: no push (Agent View reports it)"; exit 0; }
     case "$ev:$t" in
       Notification:permission_prompt|Notification:elicitation_dialog) kind="needs input" ;;
       Stop:) kind="done" ;;
       *) log "not a push event"; exit 0 ;;
     esac ;;
esac
msg=$(j '.message // .last_assistant_message' | tr '\n' ' ' | cut -c1-140)
prio=default; tags=white_check_mark
[ "$kind" = "needs input" ] && { prio=high; tags=warning; }
click=https://claude.ai/code; via="Click: Code tab"              # tap opens the Claude app's Code tab …
[ -n "${CLAUDE_CODE_BRIDGE_SESSION_ID:-}" ] && { click="$click/$CLAUDE_CODE_BRIDGE_SESSION_ID"; via="with Click"; }  # … or the session
if ${AGENT_PUSH_CURL:-curl} -fsS -m 5 -H "Title: ${AGENT_HOST:-$(hostname -s)} · $kind" -H "Priority: $prio" \
     -H "Tags: $tags" -H "Click: $click" -d "${msg:-$kind}" \
     -K <(printf 'url = "%s/%s"\n' "${NTFY_SERVER:-https://ntfy.sh}" "$topic") >/dev/null 2>&1   # topic not in argv
then log "pushed \"$kind\" ($via)"
else log "push \"$kind\" FAILED (curl)"; fi
exit 0
