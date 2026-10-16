#!/usr/bin/env bats
# mac-remote-access.bats — add-key validation/idempotence and apply (lockout guard, backup outside the Include dir,
# sshd -t rollback, idempotence) against scratch dirs and fake sudo/sshd/pmset/socketfilterfw.

setup() {
  REPO="$BATS_TEST_DIRNAME/.."
  MRA="$REPO/bin/mac-remote-access"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.ssh"
  F="$BATS_TEST_TMPDIR/fake"; mkdir -p "$F" "$BATS_TEST_TMPDIR/etc/sshd_config.d"
  export MRA_SSHD_DIR="$BATS_TEST_TMPDIR/etc/sshd_config.d" MRA_BAK_DIR="$BATS_TEST_TMPDIR/etc" CC_SUDO=
  export PM_STATE="$BATS_TEST_TMPDIR/pm"; printf 'sleep 10\ndisplaysleep 10\n' > "$PM_STATE"
  cat > "$F/pmset" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = -g ]; then printf 'Battery Power:\n sleep                1\nAC Power:\n'; sed 's/^/ /' "$PM_STATE"; exit 0; fi
echo "pmset $*" >> "$PM_STATE.log"; printf 'sleep 0\ndisplaysleep 10\n' > "$PM_STATE"
EOF
  printf '#!/usr/bin/env bash\necho "fw $*" >> "%s/fw.log"\n[ "$1" = --listapps ] && printf "1 : %s \\n  (Allow incoming connections)\\n" "$(realpath /opt/homebrew/bin/mosh-server 2>/dev/null)"\nexit 0\n' "$BATS_TEST_TMPDIR" > "$F/fw"
  printf '#!/usr/bin/env bash\nexit ${SSHD_RC:-0}\n' > "$F/sshd"
  # like the real selftest: KEY_LOGIN=ok first, then more output (a `| grep -q` reader would SIGPIPE it)
  printf '#!/usr/bin/env bash\necho KEY_LOGIN=ok\nsleep 0.2\nseq 1 200000 | sed s/^/MORE=/\n' > "$F/selftest-ok"
  printf '#!/usr/bin/env bash\necho KEY_LOGIN=failed\n' > "$F/selftest-bad"
  chmod +x "$F"/*
  export MRA_PMSET="$F/pmset" MRA_FW="$F/fw" MRA_SSHD="$F/sshd" MRA_SELFTEST="$F/selftest-ok"
  ssh-keygen -q -t ed25519 -N '' -C moshi@iphone -f "$BATS_TEST_TMPDIR/moshi"
}

@test "add-key appends a public key once, backs up, 0600" {
  printf 'ssh-ed25519 AAAAexisting other\n' > "$HOME/.ssh/authorized_keys"
  run "$MRA" add-key "$BATS_TEST_TMPDIR/moshi.pub"
  [ "$status" -eq 0 ] && [[ "$output" == *"added"*"moshi@iphone"* ]] || { echo "$output"; return 1; }
  [ "$(wc -l < "$HOME/.ssh/authorized_keys" | tr -d ' ')" = 2 ]
  [ "$(stat -f %Lp "$HOME/.ssh/authorized_keys" 2>/dev/null || stat -c %a "$HOME/.ssh/authorized_keys")" = 600 ]
  ls "$HOME/.ssh/authorized_keys".bak.* >/dev/null
  run "$MRA" add-key - < "$BATS_TEST_TMPDIR/moshi.pub"
  [ "$status" -eq 0 ] && [ "$output" = "add-key: already present" ]
  [ "$(wc -l < "$HOME/.ssh/authorized_keys" | tr -d ' ')" = 2 ]
}

@test "add-key refuses private keys, garbage and several keys" {
  run "$MRA" add-key "$BATS_TEST_TMPDIR/moshi"
  [ "$status" -ne 0 ] && [[ "$output" == *"PRIVATE key"* ]]
  [[ "$output" != *"OPENSSH PRIVATE KEY-----"$'\n'* ]]
  run "$MRA" add-key - <<<"not a key"
  [ "$status" -ne 0 ] && [[ "$output" == *"not a valid public key"* ]]
  run "$MRA" add-key - < <(cat "$BATS_TEST_TMPDIR/moshi.pub" "$BATS_TEST_TMPDIR/moshi.pub")
  [ "$status" -ne 0 ] && [[ "$output" == *"exactly one"* ]]
  [ ! -e "$HOME/.ssh/authorized_keys" ]
}

@test "apply refuses without a phone key or a working key login (lockout guard)" {
  run "$MRA" apply
  [ "$status" -ne 0 ] && [[ "$output" == *"no phone key"* ]]
  "$MRA" add-key "$BATS_TEST_TMPDIR/moshi.pub" >/dev/null
  MRA_SELFTEST="$F/selftest-bad" run "$MRA" apply
  [ "$status" -ne 0 ] && [[ "$output" == *"does not work"* ]]
  [ ! -e "$MRA_SSHD_DIR/100-keys-only.conf" ]
  [ ! -e "$PM_STATE.log" ]
}

@test "apply installs the drop-in and sleep settings once; 2nd run changes nothing" {
  "$MRA" add-key "$BATS_TEST_TMPDIR/moshi.pub" >/dev/null
  run "$MRA" apply
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  cmp "$REPO/config/mac/sshd-100-keys-only.conf" "$MRA_SSHD_DIR/100-keys-only.conf"
  grep -qx 'pmset -c sleep 0 displaysleep 10' "$PM_STATE.log"
  run "$MRA" apply
  [ "$status" -eq 0 ] && [[ "$output" == *"mac-remote-access apply: no changes"* ]]
  [ "$(wc -l < "$PM_STATE.log" | tr -d ' ')" = 1 ]
}

@test "apply backs up a different drop-in outside sshd_config.d and rolls back when sshd -t fails" {
  "$MRA" add-key "$BATS_TEST_TMPDIR/moshi.pub" >/dev/null
  echo 'PasswordAuthentication yes' > "$MRA_SSHD_DIR/100-keys-only.conf"
  SSHD_RC=1 run "$MRA" apply
  [ "$status" -ne 0 ] && [[ "$output" == *"rolling back"* ]]
  [ "$(cat "$MRA_SSHD_DIR/100-keys-only.conf")" = 'PasswordAuthentication yes' ]
  ls "$MRA_BAK_DIR"/100-keys-only.conf.bak.* >/dev/null
  [ -z "$(ls "$MRA_SSHD_DIR" | grep bak)" ]
}

@test "the drop-in is keys-only for nicolas" {
  c="$REPO/config/mac/sshd-100-keys-only.conf"
  grep -qx 'PasswordAuthentication no' "$c"
  grep -qx 'KbdInteractiveAuthentication no' "$c"
  grep -qx 'PermitRootLogin no' "$c"
  grep -qx 'AllowUsers nicolas' "$c"
}
