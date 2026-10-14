#!/usr/bin/env bats
# repo.bats — structural checks: layout, JSON validity, allowlist format, and no secrets in the repo.

setup() {
  cd "$BATS_TEST_DIRNAME/.."
}

files() { git ls-files --cached --others --exclude-standard; }

@test "core docs exist" {
  for f in CLAUDE.md README.md docs/architecture.md docs/spec.md \
           docs/runbooks/00-bootstrap-from-zero.md docs/runbooks/add-repo.md docs/runbooks/verify.md; do
    [ -s "$f" ] || { echo "missing $f"; return 1; }
  done
}

@test "every runbook listed in the plan exists" {
  for r in 00-bootstrap-from-zero mac-rebuild cloud-rebuild iphone-setup add-repo remove-repo \
           sync-settings rotate-secrets upgrade-claude-code troubleshooting verify tailscale; do
    [ -s "docs/runbooks/$r.md" ] || { echo "missing docs/runbooks/$r.md"; return 1; }
  done
}

@test "ADRs are numbered and have a status" {
  n=0
  for f in docs/decisions/[0-9][0-9][0-9][0-9]-*.md; do
    grep -q '^- Status:' "$f" || { echo "$f has no Status"; return 1; }
    n=$((n + 1))
  done
  [ "$n" -ge 5 ]
}

@test "relative markdown links resolve" {
  bad=0
  while IFS= read -r md; do
    dir=$(dirname "$md")
    for link in $(grep -oE '\]\([^)#]+' "$md" | sed 's/^](//' | grep -vE '^(https?:|mailto:)'); do
      [ -e "$dir/$link" ] || { echo "$md → $link"; bad=1; }
    done
  done < <(files | grep '\.md$' | grep -v '^prompts/')
  [ "$bad" -eq 0 ]
}

@test "JSON config files parse" {
  while IFS= read -r f; do
    jq empty "$f" || { echo "invalid JSON: $f"; return 1; }
  done < <(files | grep '\.json$')
}

@test "repos.txt entries are bare directory names" {
  for f in config/mac/repos.txt config/cloud/repos.txt; do
    [ -f "$f" ]
    run grep -vE '^[[:space:]]*(#|$)|^[A-Za-z0-9._-]+[[:space:]]*(#.*)?$' "$f"
    [ "$status" -eq 1 ] || { echo "bad lines in $f: $output"; return 1; }
  done
}

@test "no secrets in the repo" {
  # Tailscale keys, GitHub tokens, Anthropic keys, private keys, OAuth tokens, ntfy topic URLs
  pat='tskey-[a-z]+-[A-Za-z0-9]{8,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-ant-[A-Za-z0-9_-]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|ntfy\.sh/[0-9a-f]{32}'
  run bash -c "git ls-files --cached --others --exclude-standard -z -- . ':!tests/repo.bats' | xargs -0 grep -sIlE '$pat' --"
  [ -z "$output" ] || { echo "possible secret in: $output"; return 1; }
}

@test "shell scripts are executable" {
  while IFS= read -r f; do
    [ -x "$f" ] || { echo "not executable: $f"; return 1; }
  done < <(tests/shell-files.sh)
}
