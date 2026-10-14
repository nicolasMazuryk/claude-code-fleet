#!/usr/bin/env bash
# shell-files.sh — list every shell script in the repo (tracked or new, not ignored), one per line.
# Used by `make lint`. A file counts if it ends in .sh/.bash or has a sh/bash shebang.
set -euo pipefail
cd "$(dirname "$0")/.."
git ls-files --cached --others --exclude-standard -- . ':!prompts/' |
while IFS= read -r f; do
  [ -f "$f" ] || continue
  case $f in
    *.sh|*.bash) echo "$f" ;;
    *.md|*.json|*.txt|*.hujson|*.plist|*.tmpl|*.service|*.conf|*.mp3|*.bats|Makefile|.gitignore) ;;
    *) head -n1 "$f" | grep -qE '^#!.*\b(ba)?sh\b' && echo "$f" ;;
  esac
done
