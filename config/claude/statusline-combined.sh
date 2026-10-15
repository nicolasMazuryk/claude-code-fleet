#!/bin/bash
# Combined status line: ccstatusline (state) + claude-hud (activity).
# node and ccstatusline come from PATH; when PATH has no node (launchd/tmux shells), use nvm's default-alias node
# (newest installed version matching ~/.nvm/alias/default, else the newest installed). No hardcoded version.
input=$(cat)
if ! command -v node >/dev/null 2>&1; then
  nvm_dir=${NVM_DIR:-$HOME/.nvm}
  alias_v=$(cat "$nvm_dir/alias/default" 2>/dev/null)
  for pat in "v${alias_v#v}" v; do
    # shellcheck disable=SC2012  # nvm version dirs are plain vX.Y.Z names
    bin=$(ls -d "$nvm_dir/versions/node/$pat"*/bin 2>/dev/null | sort -V | tail -n1)
    [ -n "$bin" ] && break
  done
  [ -n "$bin" ] && PATH="$bin:$PATH"
fi
printf '%s' "$input" | ccstatusline
hud=$(printf '%s' "$input" | node "$HOME/.claude/plugins/claude-hud/statusline.mjs" 2>/dev/null | sed "s/Today //")
[ -n "$hud" ] && printf '%s' "$hud"
exit 0
