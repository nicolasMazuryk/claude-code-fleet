#!/usr/bin/env bash
# agent-push.sh — Claude Code hook (Notification + Stop): push to the iPhone via ntfy only when you're away from the
# MacBook (agent-present fails). Same file on both hosts; installed to ~/.claude/hooks/agent-push.sh by install.sh.
# Topic: ~/.config/agent-push/topic (0600, never in git). Exits 0 always so it can never block a session.
# Test hooks: AGENT_PRESENT (command, default ~/.local/bin/agent-present), NTFY_SERVER, AGENT_PUSH_CURL.
# shellcheck disable=SC1091
. "$HOME/.config/cc-orchestrator/config" 2>/dev/null
p=$(cat)
${AGENT_PRESENT:-"$HOME/.local/bin/agent-present"} && exit 0     # at the Mac: sounds are enough
topic=$(cat "$HOME/.config/agent-push/topic" 2>/dev/null) || exit 0
[ -n "$topic" ] || exit 0
j() { jq -r "$1 // empty" <<<"$p" 2>/dev/null; }
[ -n "$(j .agent_id)" ] && exit 0                                 # subagent events
ev=$(j .hook_event_name); t=$(j .notification_type)
case "$ev:$t" in
  Notification:agent_needs_input) kind="needs input" ;;           # Agent View, for any background session
  Notification:agent_completed)   kind="done" ;;
  *) [ -n "${CLAUDE_JOB_DIR:-}" ] && exit 0                       # a background session: Agent View reports it
     case "$ev:$t" in
       Notification:permission_prompt|Notification:elicitation_dialog) kind="needs input" ;;
       Stop:) kind="done" ;;
       *) exit 0 ;;
     esac ;;
esac
msg=$(j '.message // .last_assistant_message' | tr '\n' ' ' | cut -c1-140)
prio=default; tags=white_check_mark
[ "$kind" = "needs input" ] && { prio=high; tags=warning; }
click=()                                                          # tap opens the session in the Claude app
[ -n "${CLAUDE_CODE_BRIDGE_SESSION_ID:-}" ] && click=(-H "Click: https://claude.ai/code/$CLAUDE_CODE_BRIDGE_SESSION_ID")
${AGENT_PUSH_CURL:-curl} -fsS -m 5 -H "Title: ${AGENT_HOST:-$(hostname -s)} · $kind" -H "Priority: $prio" -H "Tags: $tags" \
  ${click[@]+"${click[@]}"} -d "${msg:-$kind}" "${NTFY_SERVER:-https://ntfy.sh}/$topic" >/dev/null 2>&1
exit 0
