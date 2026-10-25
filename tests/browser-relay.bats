#!/usr/bin/env bats
# browser-relay.bats — the browser-router relay (browser-router docs/contracts.md §7): the Mac handler (CDP lease,
# forward over the ControlMaster socket, release, dispatch), the hash-checked slot in agent-relay, the mac-up payload,
# and the cloud writer. Fake ssh / chrome / claude / pgrep / agent-browser live in $BATS_TEST_TMPDIR; nothing real runs.

setup() {
  REPO="$BATS_TEST_DIRNAME/.."
  T="$BATS_TEST_TMPDIR"
  export HOME="$T/mac"
  mkdir -p "$HOME/.claude" "$HOME/.local/bin" "$T/fake" "$T/agents/repo1"
  export BROWSER_RELAY_STATE="$T/relay" AGENT_RELAY_HOST=cloud AGENT_RELAY_CM="$T/cm.sock"
  export AGENT_RELAY_SSH="$T/fake/ssh" SSH_LOG="$T/ssh.log" FWD_FAIL="$T/fwd-fail"
  export BROWSER_CHROME_BIN="$T/fake/chrome" CHROME_LOG="$T/chrome.log" CHROME_PID="$T/chrome.pid"
  export BROWSER_AGENT_PROFILES="$T/profiles" BROWSER_PORT_MIN=9390 BROWSER_PORT_MAX=9396 BROWSER_READY_SECS=5
  export BROWSER_CLAUDE_BIN="$T/fake/claude" CLAUDE_LOG="$T/claude.log" BROWSER_AGENTS_ROOT="$T/agents"
  : > "$SSH_LOG"
  cat > "$T/fake/ssh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$SSH_LOG"
case "$*" in *"-O forward"*) [ -e "$FWD_FAIL" ] && exit 255 ;; esac
exit 0
EOF
  cat > "$T/fake/chrome" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$CHROME_LOG"; echo $$ > "$CHROME_PID"
for a in "$@"; do case $a in --remote-debugging-port=*) p=${a#*=} ;; esac; done
exec perl -MIO::Socket::INET -e '$s = IO::Socket::INET->new(LocalAddr => "127.0.0.1", LocalPort => shift, Listen => 5, ReuseAddr => 1) or die; while (1) { $c = $s->accept; close $c if $c }' "$p"
EOF
  cat > "$T/fake/claude" <<'EOF'
#!/usr/bin/env bash
{ echo "argc=$#"; echo "pwd=$PWD"; for a in "$@"; do printf 'arg=%s\n' "$a"; done; } >> "$CLAUDE_LOG"
exit "${CLAUDE_RC:-0}"
EOF
  chmod +x "$T/fake/ssh" "$T/fake/chrome" "$T/fake/claude"
  P="t${BATS_TEST_NUMBER}x"   # id prefix, so teardown finds this test's watchers
}

teardown() {
  pkill -f "browser-relay-handler release-expired $P" 2>/dev/null || true
  local f
  for f in "$T"/relay/leases/*; do
    [ -f "$f" ] && kill "$(cut -d' ' -f2 "$f")" 2>/dev/null
  done
  [ -f "$CHROME_PID" ] && kill "$(cat "$CHROME_PID")" 2>/dev/null
  return 0
}

waitfor() { local i; for i in $(seq 1 60); do eval "$1" && return 0; sleep 0.1; done; return 1; }
sha16() { printf %s "$1" | shasum -a 256 | cut -c1-16; }
handler() { # handler <event> <payload-json> [stdin of the relay: closed fd 3 so bats does not wait for children]
  printf '%s' "$2" | BROWSER_RELAY_EVENT="$1" "$REPO/bin/browser-relay-handler" 3>&- || true
}
lease_ev() { handler BrowserLease "$(jq -nc --arg id "$1" --arg p "$2" --argjson t "${3:-900}" \
  '{id: $id, site: "justjoin.it", profile: $p, session_id: "s1", ttl_s: $t}')"; }
spooled() { cat "$T"/relay/out/*.out 2>/dev/null | sort; }
alive() { kill -0 "$(cat "$CHROME_PID")" 2>/dev/null; }

# ---------------------------------------------------------------------------------------------- lease

@test "lease: headed Chrome on loopback in the port range, forwarded over the ControlMaster socket, lease-ready spooled" {
  lease_ev "${P}1" shield
  line=$(spooled); [[ $line == "lease-ready ${P}1 939"[0-6] ]] || { echo "$line"; return 1; }
  port=${line##* }
  [ "$(wc -l < "$CHROME_LOG" | tr -d ' ')" -eq 1 ]
  grep -qF -- "--user-data-dir=$T/profiles/shield" "$CHROME_LOG"
  grep -qF -- "--remote-debugging-port=$port" "$CHROME_LOG"
  grep -qF -- "--remote-debugging-address=127.0.0.1" "$CHROME_LOG"
  [ -d "$T/profiles/shield" ]
  [ "$(cat "$SSH_LOG")" = "-S $T/cm.sock -O forward -R 127.0.0.1:$port:127.0.0.1:$port cloud" ]
  [ "$(cut -d' ' -f1 "$T/relay/leases/${P}1")" = "$port" ]
}

@test "lease: the same id twice is idempotent (one browser, one forward, same port)" {
  lease_ev "${P}1" shield
  rm -f "$T"/relay/out/*.out
  lease_ev "${P}1" shield
  [[ $(spooled) == "lease-ready ${P}1 939"[0-6] ]]
  [ "$(wc -l < "$CHROME_LOG" | tr -d ' ')" -eq 1 ]
  [ "$(wc -l < "$SSH_LOG" | tr -d ' ')" -eq 1 ]
}

@test "lease: two leases get different ports" {
  lease_ev "${P}1" a; lease_ev "${P}2" b
  [ "$(spooled | awk '{print $3}' | sort -u | wc -l | tr -d ' ')" -eq 2 ]
}

@test "lease: a profile that is not a bare name, or a bad id, starts no browser" {
  lease_ev "${P}1" '../x'; lease_ev "${P}2" 'a/b'; lease_ev "${P}3" '.hidden'
  [ "$(spooled | grep -c bad_profile)" -eq 3 ]
  lease_ev 'a b' shield; lease_ev '../x' shield; lease_ev 'x;touch pwned' shield
  [ ! -e "$CHROME_LOG" ] && [ ! -s "$SSH_LOG" ]
  [ "$(spooled | wc -l | tr -d ' ')" -eq 3 ]
  handler BrowserLease '{"id":"'"${P}9"'","profile":"shield","ttl_s":"1;id"}'
  spooled | grep -q "lease-failed ${P}9 bad_ttl"
  [ ! -e "$CHROME_LOG" ]
}

@test "lease: no Chrome binary -> lease-failed chrome_missing" {
  BROWSER_CHROME_BIN="$T/nope" lease_ev "${P}1" shield
  [ "$(spooled)" = "lease-failed ${P}1 chrome_missing" ]
  [ ! -s "$SSH_LOG" ]
}

@test "lease: forward fails -> lease-failed forward_failed, Chrome killed, no lease file" {
  touch "$FWD_FAIL"
  lease_ev "${P}1" shield
  [ "$(spooled)" = "lease-failed ${P}1 forward_failed" ]
  waitfor '! alive'
  [ ! -e "$T/relay/leases/${P}1" ]
}

# --------------------------------------------------------------------------------------------- release

@test "release: forward cancelled with the same -R spec, Chrome closed, lease gone, release-ok" {
  lease_ev "${P}1" shield
  port=$(spooled | awk '{print $3}'); rm -f "$T"/relay/out/*.out
  alive
  handler BrowserRelease "{\"id\":\"${P}1\"}"
  [ "$(tail -n1 "$SSH_LOG")" = "-S $T/cm.sock -O cancel -R 127.0.0.1:$port:127.0.0.1:$port cloud" ]
  waitfor '! alive'
  [ ! -e "$T/relay/leases/${P}1" ]
  [ "$(spooled)" = "release-ok ${P}1" ]
}

@test "release: unknown id is idempotent (release-ok, no ssh call)" {
  handler BrowserRelease '{"id":"nothing-here"}'
  [ "$(spooled)" = "release-ok nothing-here" ]
  [ ! -s "$SSH_LOG" ]
  handler BrowserRelease '{"id":"../x"}'
  [ "$(spooled | wc -l | tr -d ' ')" -eq 1 ]
}

@test "release: the ttl watcher releases an expired lease" {
  lease_ev "${P}1" shield 1
  [ -f "$T/relay/leases/${P}1" ]
  waitfor '[ ! -e "$T/relay/leases/${P}1" ]'
  grep -q -- "-O cancel -R" "$SSH_LOG"
  waitfor '! alive'
}

# -------------------------------------------------------------------------- relay slot + dispatch

relay_setup() { # relay_setup [matcher]: settings.json with the handler in the SessionStart slot
  CMD="$REPO/bin/browser-relay-handler"
  SUM=$(sha16 "$CMD")
  export AGENT_RELAY_SETTINGS="$HOME/.claude/settings.json"
  jq -n --arg c "$CMD" --arg m "${1:-browser-router-relay}" \
    '{hooks: {SessionStart: [{matcher: "startup", hooks: [{type: "command", command: "echo other"}]},
                             {matcher: $m, hooks: [{type: "command", command: $c}]}]}}' > "$AGENT_RELAY_SETTINGS"
  LOG="$T/relay.log"
}
bev() { # bev <event> <group> <sum> <payload-json>
  jq -nc --arg e "$1" --argjson g "$2" --arg s "$3" --argjson p "$4" --argjson ts "$(date +%s)" \
    '{event: $e, group: $g, handler: 0, sum: $s, ts: $ts, payload: $p}'
}
djob() { jq -nc --arg id "$1" --arg ex "${2:-mac-computer-use}" --arg task "$3" --arg cwd "${4:-/data/fleet/repo1}" \
  '{job_id: $id, site: "linkedin.com", task: $task, cwd: $cwd, executor: $ex}'; }
relay() { "$REPO/bin/agent-relay" --handle 2>> "$LOG" 3>&-; }

@test "dispatch through the relay: hash matches, claude -p gets the task as one argv, cwd mapped to AGENTS_ROOT/<basename>" {
  relay_setup
  task='say "hi" $(touch '"$T"'/pwned) `touch '"$T"'/pwned2` '"'"'; x'
  bev BrowserDispatch 0 "$SUM" "$(djob job1 mac-computer-use "$task")" | relay
  waitfor 'spooled | grep -q "dispatch-done job1 0"'
  spooled | grep -qx "dispatch-ok job1"
  grep -q 'ran BrowserDispatch/0/0' "$LOG"
  [ "$(grep -c '^argc=' "$CLAUDE_LOG")" -eq 1 ]
  grep -qx 'argc=2' "$CLAUDE_LOG"; grep -qx 'arg=-p' "$CLAUDE_LOG"
  grep -qxF "arg=$task" "$CLAUDE_LOG"
  grep -qE "^pwd=.*/agents/repo1$" "$CLAUDE_LOG"
  [ ! -e "$T/pwned" ] && [ ! -e "$T/pwned2" ]
}

@test "dispatch: unknown cwd runs in HOME; the claude exit code is reported" {
  relay_setup
  CLAUDE_RC=3 bev BrowserDispatch 0 "$SUM" "$(djob job2 mac-computer-use hello /somewhere/else)" | CLAUDE_RC=3 relay
  waitfor 'spooled | grep -q "dispatch-done job2 3"'
  grep -qE "^pwd=.*/mac$" "$CLAUDE_LOG"
}

@test "dispatch: wrong hash, group != 0, another matcher and a foreign executor are refused" {
  relay_setup
  { bev BrowserDispatch 0 0123456789abcdef "$(djob j1 mac-computer-use t)"
    bev BrowserDispatch 1 "$SUM" "$(djob j2 mac-computer-use t)"; } | relay
  sleep 0.5; [ ! -e "$CLAUDE_LOG" ]
  [ "$(grep -c 'skipped' "$LOG")" -eq 2 ]
  relay_setup some-other-matcher
  bev BrowserDispatch 0 "$SUM" "$(djob j3 mac-computer-use t)" | relay
  sleep 0.5; [ ! -e "$CLAUDE_LOG" ]
  [ "$(grep -c 'skipped' "$LOG")" -eq 3 ]
  relay_setup
  bev BrowserDispatch 0 "$SUM" "$(djob j4 mac-chrome t)" | relay
  waitfor 'spooled | grep -q "dispatch-done j4 126"'
  [ ! -e "$CLAUDE_LOG" ]
  bev BrowserDispatch 0 "$SUM" "$(djob 'j 5' mac-computer-use t)" | relay
  sleep 0.5; [ ! -e "$CLAUDE_LOG" ]
}

@test "relay: BrowserLease via the slot passes the event name; BrowserRelease releases" {
  relay_setup
  bev BrowserLease 0 "$SUM" "{\"id\":\"${P}1\",\"site\":\"x.com\",\"profile\":\"shield\",\"session_id\":\"s\",\"ttl_s\":900}" | relay
  waitfor 'spooled | grep -q "lease-ready ${P}1"'
  bev BrowserRelease 0 "$SUM" "{\"id\":\"${P}1\"}" | relay
  waitfor 'spooled | grep -q "release-ok ${P}1"'
  grep -q -- "-O cancel" "$SSH_LOG"
}

# ------------------------------------------------------------------------------------------- mac-up

fixture_app() { # fixture_app <dir.app> <version>
  mkdir -p "$1/Contents"
  plutil -create xml1 "$1/Contents/Info.plist"
  plutil -insert CFBundleShortVersionString -string "$2" "$1/Contents/Info.plist"
}
fixture_ext() { # fixture_ext <dir> <version>
  mkdir -p "$1/$2"; printf '{"version":"%s"}' "$2" > "$1/$2/manifest.json"
}
seed_selftest() { # seed_selftest <status> <executor>... : selftest.json recorded at the fixture versions
  local st=$1; shift
  mkdir -p "$T/state"
  printf '%s\n' "$@" | jq -Rn --arg st "$st" '{schema: 1, executors: ([inputs] | map({key: ., value: {status: $st, ran_at: 1, failed: [],
    versions: {dia: "1.53.0", chrome: "155.0.8059.85", claude_in_chrome: "1.0.101", agent_browser: "0.39.1"}}}) | from_entries)}' \
    > "$T/state/selftest.json"
}
up() { # up: browser-up with the fixtures; $RUNNING lists running process names
  printf '#!/bin/sh\n[ "$1" = -x ] && grep -qxF "$2" "%s"\n' "$T/running" > "$T/fake/pgrep"; chmod +x "$T/fake/pgrep"
  BROWSER_UP_PGREP="$T/fake/pgrep" BROWSER_UP_NOW=1000 BROWSER_ROUTER_STATE="$T/state" \
    BROWSER_UP_DIA_APP="$T/Dia.app" BROWSER_UP_CHROME_APP="$T/Chrome.app" BROWSER_UP_EXT_DIRS="$T/ext1:$T/ext2" \
    "$REPO/bin/browser-up"
}

@test "browser-up: running state, versions (highest extension version) and executors" {
  fixture_app "$T/Dia.app" 1.53.0; fixture_app "$T/Chrome.app" 155.0.8059.85
  fixture_ext "$T/ext1" 1.0.99; fixture_ext "$T/ext1" 1.0.101; fixture_ext "$T/ext2" 1.0.100
  printf '#!/bin/sh\necho "agent-browser 0.39.1"\n' > "$HOME/.local/bin/agent-browser"; chmod +x "$HOME/.local/bin/agent-browser"
  printf 'Dia\n' > "$T/running"
  seed_selftest ok mac-chrome mac-computer-use agent-browser
  out=$(up)
  [ "$(wc -l <<<"$out" | tr -d ' ')" -eq 1 ]
  [ "$(jq -S . <<<"$out")" = "$(jq -S . <<<'{"schema":1,"ts":1000,"dia_running":true,"chrome_running":false,
    "versions":{"dia":"1.53.0","chrome":"155.0.8059.85","claude_in_chrome":"1.0.101","agent_browser":"0.39.1"},
    "executors":{"mac-chrome":"ok","mac-computer-use":"not built","agent-browser":"ok"}}')" ]
  printf 'Google Chrome\n' > "$T/running"
  out=$(up)
  [ "$(jq -c '[.dia_running, .chrome_running, .executors["mac-chrome"], .executors["agent-browser"]]' <<<"$out")" = '[false,true,"down","ok"]' ]
}

@test "browser-up: up executors without a passing selftest are untrusted, down stays down" {
  fixture_app "$T/Dia.app" 1.53.0; fixture_app "$T/Chrome.app" 155.0.8059.85
  fixture_ext "$T/ext1" 1.0.101
  printf '#!/bin/sh\necho "agent-browser 0.39.1"\n' > "$HOME/.local/bin/agent-browser"; chmod +x "$HOME/.local/bin/agent-browser"
  printf 'Dia\n' > "$T/running"
  # no record at all
  [ "$(up | jq -c .executors)" = '{"mac-chrome":"untrusted","mac-computer-use":"not built","agent-browser":"untrusted"}' ]
  # failed record for one, passing for another, none for the third
  seed_selftest untrusted mac-chrome; jq '.executors["agent-browser"] = .executors["mac-chrome"] | .executors["agent-browser"].status = "ok"' "$T/state/selftest.json" > "$T/s" && mv "$T/s" "$T/state/selftest.json"
  [ "$(up | jq -c .executors)" = '{"mac-chrome":"untrusted","mac-computer-use":"not built","agent-browser":"ok"}' ]
  # unreadable record
  echo 'not json' > "$T/state/selftest.json"
  [ "$(up | jq -c '.executors["agent-browser"]')" = '"untrusted"' ]
  # Dia not running: down regardless of the record
  seed_selftest ok mac-chrome mac-computer-use agent-browser
  : > "$T/running"
  [ "$(up | jq -c '[.executors["mac-chrome"], .executors["agent-browser"]]')" = '["down","ok"]' ]
}

@test "browser-up: a recorded version that differs from the current one makes every executor untrusted" {
  fixture_app "$T/Dia.app" 1.53.0; fixture_app "$T/Chrome.app" 155.0.8059.85
  fixture_ext "$T/ext1" 1.0.101
  printf '#!/bin/sh\necho "agent-browser 0.39.2"\n' > "$HOME/.local/bin/agent-browser"; chmod +x "$HOME/.local/bin/agent-browser"
  printf 'Dia\n' > "$T/running"
  seed_selftest ok mac-chrome mac-computer-use agent-browser   # recorded agent_browser 0.39.1, now 0.39.2
  # any version change stales every record, as in browser-router's executorTrust
  [ "$(up | jq -c .executors)" = '{"mac-chrome":"untrusted","mac-computer-use":"not built","agent-browser":"untrusted"}' ]
}

@test "browser-up: unreadable versions are left out, nothing running -> executors down" {
  : > "$T/running"
  PATH="$T/fake:/usr/bin:/bin:/usr/sbin" out=$(up)
  [ "$(jq -S . <<<"$out")" = "$(jq -S . <<<'{"schema":1,"ts":1000,"dia_running":false,"chrome_running":false,
    "versions":{},"executors":{"mac-chrome":"down","mac-computer-use":"not built","agent-browser":"down"}}')" ]
}

# --------------------------------------------------------------------------------------- cloud side

cloud_setup() {
  CLOUD="$T/cloud"; EV="$CLOUD/.local/state/agent-events"
  mkdir -p "$CLOUD/.local/bin" "$CLOUD/.claude"
  ln -s "$REPO/bin/browser-relay-cloud" "$CLOUD/.local/bin/browser-relay-cloud"
  export BROWSER_ROUTER_EVENTS="$EV" BROWSER_ROUTER_BIN="$T/fake/br" BR_LOG="$T/br.log"
  printf '#!/bin/sh\necho "$*" >> "$BR_LOG"\n' > "$T/fake/br"; chmod +x "$T/fake/br"
  CMD="~/.local/libexec/cc-orchestrator/browser-relay-handler"
  export BROWSER_RELAY_SETTINGS="$CLOUD/.claude/settings.json"
  jq -n --arg c "$CMD" '{hooks: {SessionStart: [{matcher: "browser-router-relay", hooks: [{type: "command", command: $c}]}]}}' \
    > "$BROWSER_RELAY_SETTINGS"
  unset BROWSER_ROUTER_RELAY_SUM
}
cline() { "$REPO/bin/browser-relay-cloud" line "$1"; }
replies() { ls "$EV/replies" 2>/dev/null; }

@test "cloud writer: mac-up must be a schema-1 JSON object; written atomically as one compact line" {
  cloud_setup
  cline 'mac-up {"schema":1,"ts":5,"dia_running":true,  "versions":{}}'
  [ "$(cat "$EV/mac-up")" = '{"schema":1,"ts":5,"dia_running":true,"versions":{}}' ]
  rm "$EV/mac-up"
  cline 'mac-up [1,2]'; cline 'mac-up not json'; cline 'mac-up {"schema":2,"ts":1}'; cline 'mac-up {"schema":1}'
  [ ! -e "$EV/mac-up" ]
  ls "$EV" | grep -vq . || true
  [ -z "$(ls -A "$EV" 2>/dev/null)" ]
}

@test "cloud writer: replies land in replies/<id>; bad ids, ports and reasons are dropped" {
  cloud_setup
  cline 'lease-ready abc-1 9301'; cline 'lease-failed abc-2 no_free_port'; cline 'release-ok abc-3'; cline 'dispatch-ok job_4'
  [ "$(cat "$EV/replies/abc-1")" = 'lease-ready abc-1 9301' ]
  [ "$(cat "$EV/replies/abc-2")" = 'lease-failed abc-2 no_free_port' ]
  [ "$(cat "$EV/replies/abc-3")" = 'release-ok abc-3' ]
  [ "$(cat "$EV/replies/job_4")" = 'dispatch-ok job_4' ]
  rm -rf "$EV/replies"
  cline 'lease-ready abc 9400'; cline 'lease-ready abc 22'; cline 'lease-ready abc 93011'; cline 'lease-ready ../x 9301'
  cline 'lease-ready a/b 9301'; cline 'lease-failed abc Bad_Reason'; cline 'lease-failed abc two words'
  cline 'release-ok ../etc'; cline 'dispatch-ok a;b'; cline 'present'; cline 'garbage line'
  [ -z "$(replies)" ]
  [ ! -e "$EV/../etc" ] && [ ! -e "$EV/x" ]
}

@test "cloud writer: dispatch-done writes the reply and runs browser-router vault finish <job> --exit <n>" {
  cloud_setup
  cline 'dispatch-done job1 3'
  [ "$(cat "$EV/replies/job1")" = 'dispatch-done job1 3' ]
  [ "$(cat "$BR_LOG")" = 'vault finish job1 --exit 3' ]
  : > "$BR_LOG"
  cline 'dispatch-done job2 x'; cline 'dispatch-done job3 1000'; cline 'dispatch-done ../j 0'
  [ ! -s "$BR_LOG" ] && [ ! -e "$EV/replies/job2" ]
}

@test "cloud: sum is sha256[:16] of the relay handler command; no handler -> error" {
  cloud_setup
  run "$REPO/bin/browser-relay-cloud" sum
  [ "$status" -eq 0 ] && [ "$output" = "$(sha16 "$CMD")" ]
  echo '{}' > "$BROWSER_RELAY_SETTINGS"
  run "$REPO/bin/browser-relay-cloud" sum
  [ "$status" -eq 1 ]
}

@test "cloud: lease without a mac-up marker exits 5" {
  cloud_setup
  run "$REPO/bin/browser-relay-cloud" lease justjoin.it shield
  [ "$status" -eq 5 ]; [[ $output == *"Mac is down"* ]]
  [ ! -e "$EV/events.jsonl" ]
}

lease_cmd() { # lease_cmd <reply-line-template, %ID%>: run `lease` in the background, answer from here
  cloud_setup
  mkdir -p "$EV"
  echo '{"schema":1,"ts":1}' > "$EV/mac-up"
  BROWSER_RELAY_POLL=0.1 "$REPO/bin/browser-relay-cloud" lease justjoin.it shield --session s1 --ttl 60 --wait "${2:-5}" \
    > "$T/lease.out" 2> "$T/lease.err" 3>&- &
  lpid=$!
  if [ -n "$1" ]; then
    waitfor '[ -s "$EV/events.jsonl" ]'
    id=$(jq -r .payload.id "$EV/events.jsonl")
    cline "${1//%ID%/$id}"
  fi
  wait "$lpid"; lrc=$?
}

@test "cloud: lease queues a BrowserLease event, waits for the Mac's reply and prints '<id> <port>'" {
  lease_cmd 'lease-ready %ID% 9305' || true
  [ "$lrc" -eq 0 ]
  id=$(jq -r .payload.id "$EV/events.jsonl")
  [ "$(cat "$T/lease.out")" = "$id 9305" ]
  [ "$(jq -c '[.event, .group, .handler, .sum, .payload.site, .payload.profile, .payload.session_id, .payload.ttl_s]' "$EV/events.jsonl")" \
    = "[\"BrowserLease\",0,0,\"$(sha16 "$CMD")\",\"justjoin.it\",\"shield\",\"s1\",60]" ]
  "$REPO/bin/browser-relay-cloud" release "$id"
  [ "$(tail -n1 "$EV/events.jsonl" | jq -c '[.event, .payload]')" = "[\"BrowserRelease\",{\"id\":\"$id\"}]" ]
  run "$REPO/bin/browser-relay-cloud" release '../x'; [ "$status" -ne 0 ]
}

@test "cloud: lease exits 5 with the reason on lease-failed, and when the Mac does not answer" {
  lease_cmd 'lease-failed %ID% no_free_port' || true
  [ "$lrc" -eq 5 ]; grep -q no_free_port "$T/lease.err"; [ ! -s "$T/lease.out" ]
  rm -f "$EV/events.jsonl"
  lease_cmd '' 1 || true
  [ "$lrc" -eq 5 ]; grep -q 'no answer' "$T/lease.err"
}

@test "cloud writer never connects anywhere: no ssh, mosh, nc, curl, scp or rsync in the code" {
  ! grep -v '^[[:space:]]*#' "$REPO/bin/browser-relay-cloud" | grep -nE "(^|[[:space:];&|(])(ssh|mosh|nc|ncat|curl|wget|scp|rsync|telnet|socat)[[:space:]]|/dev/tcp"
}

# ------------------------------------------------------------------- end to end over a fake ssh

@test "end to end: mac-up lands in cloud's marker, a spooled reply becomes replies/<id> on cloud" {
  cloud_setup
  unset BROWSER_ROUTER_EVENTS   # cloud's default: $HOME/.local/state/agent-events with HOME=$CLOUD
  cat > "$T/fake/e2e-ssh" <<EOF
#!/usr/bin/env bash
while [ \$# -gt 1 ]; do case \$1 in -o) shift 2 ;; *) shift ;; esac; done
HOME="$CLOUD" exec bash -c "\$1"
EOF
  chmod +x "$T/fake/e2e-ssh"
  UPJSON='{"schema":1,"ts":4242,"dia_running":true,"chrome_running":false,"versions":{"dia":"1.53.0"},"executors":{"mac-chrome":"ok"}}'
  printf '#!/bin/sh\necho '"'%s'"'\n' "$UPJSON" > "$T/fake/up"; chmod +x "$T/fake/up"
  printf '#!/bin/sh\nexit 0\n' > "$T/fake/present"; chmod +x "$T/fake/present"
  LOG="$T/relay.log"
  AGENT_RELAY_SSH="$T/fake/e2e-ssh" AGENT_PRESENT="$T/fake/present" BROWSER_UP="$T/fake/up" \
    AGENT_RELAY_BEACON_SECS=1 AGENT_RELAY_TICK=0.2 "$REPO/bin/agent-relay" 2>> "$LOG" 3>&- &
  pid=$!
  waitfor 'grep -q "connected to cloud" "$LOG"'
  waitfor '[ -s "$EV/mac-up" ]'
  [ "$(jq -S . "$EV/mac-up")" = "$(jq -S . <<<"$UPJSON")" ]
  # the Mac handler's reply spool is flushed up the same connection and written by the cloud writer
  printf 'lease-ready e2e-1 9301\n' > "$T/relay/out/x.out.tmp"; mv "$T/relay/out/x.out.tmp" "$T/relay/out/x.out"
  waitfor '[ -s "$EV/replies/e2e-1" ]'
  [ "$(cat "$EV/replies/e2e-1")" = 'lease-ready e2e-1 9301' ]
  waitfor '[ ! -e "$T/relay/out/x.out" ]'
  # a foreign line is dropped by the cloud writer
  printf 'lease-ready ../evil 9301\n' > "$T/relay/out/y.out.tmp"; mv "$T/relay/out/y.out.tmp" "$T/relay/out/y.out"
  waitfor '[ ! -e "$T/relay/out/y.out" ]'
  sleep 0.3; [ "$(replies)" = e2e-1 ]
  # the relay's ssh was the ControlMaster
  kill "$pid"; wait "$pid" || true
}

@test "relay: the connection is a ControlMaster and the handler forwards on that socket" {
  grep -q 'ControlMaster=yes -o ControlPath="$AGENT_RELAY_CM"' "$REPO/bin/agent-relay"
  grep -q -- '-S "$CM" -O "$1" -R' "$REPO/bin/browser-relay-handler"
}
