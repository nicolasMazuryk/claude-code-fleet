#!/usr/bin/env bats
# browser-router-env-push.bats — Keychain → ~/.config/browser-router/env (0600), idempotent, nothing but the API key.

setup() {
  REPO="$BATS_TEST_DIRNAME/.."
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/security" <<'FAKE'
#!/usr/bin/env bash
[ "$3" = cc-browser-use-api-key ] && [ -n "${FAKE_KEY:-}" ] && { printf '%s\n' "$FAKE_KEY"; exit 0; }
exit 44
FAKE
  chmod +x "$BATS_TEST_TMPDIR/bin/security"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "writes only BROWSER_USE_API_KEY, 0600, then reports ok" {
  FAKE_KEY=k-123 run "$REPO/bin/browser-router-env-push" --local
  [ "$status" -eq 0 ]
  f="$HOME/.config/browser-router/env"
  [ "$(cat "$f")" = "BROWSER_USE_API_KEY=k-123" ]
  [ "$(stat -f %Lp "$f" 2>/dev/null || stat -c %a "$f")" = 600 ]
  FAKE_KEY=k-123 run "$REPO/bin/browser-router-env-push" --local
  [[ "$output" == *"ok local"* ]]
}

@test "no Keychain item: skipped, nothing written, exit 0" {
  run "$REPO/bin/browser-router-env-push" --local
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.config/browser-router/env" ]
}
