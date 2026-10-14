#!/bin/bash
# Combined status line: ccstatusline (state) + claude-hud (activity).
input=$(cat)
printf '%s' "$input" | ccstatusline
hud=$(printf '%s' "$input" | '/Users/nicolas/.nvm/versions/node/v24.13.0/bin/node' "$HOME/.claude/plugins/claude-hud/statusline.mjs" 2>/dev/null | sed "s/Today //")
[ -n "$hud" ] && printf '%s' "$hud"
exit 0
