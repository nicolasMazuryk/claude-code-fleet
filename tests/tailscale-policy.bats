#!/usr/bin/env bats
# tailscale-policy.bats — config/tailscale/policy.hujson keeps the network invariants (CLAUDE.md #3, #4):
# nothing sourced from tag:cloud (or "*"), Tailscale SSH members → tag:cloud as agent/ubuntu, exit node still usable.

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  POLICY=config/tailscale/policy.hujson
}

# hujson → JSON: drop // comments (whole-line or after whitespace) and trailing commas.
hujson() { perl -0pe 's{(^|\s)//[^\n]*}{$1}g; s/,(\s*[}\]])/$1/g' "$1"; }

# Print one line per invariant violation; empty output = OK.
violations() {
  hujson "$1" | jq -r '
    def srcs: (.src // []) | if type == "array" then . else [.] end;
    (((.acls // [])[], (.grants // [])[], (.ssh // [])[])
       | select(srcs | any(. == "*" or . == "tag:cloud" or startswith("tag:cloud:")))
       | "rule sourced from tag:cloud or *: \(tojson)"),
    (if (.tagOwners["tag:cloud"] // []) == [] then "tag:cloud has no tagOwners" else empty end),
    (if [(.ssh // [])[] | select(.action == "accept" and (.src | index("autogroup:member"))
                                 and (.dst | index("tag:cloud"))
                                 and (.users | index("agent")) and (.users | index("ubuntu")))] == []
     then "no ssh accept rule: autogroup:member → tag:cloud as agent, ubuntu" else empty end),
    (if [(.acls // [])[] | select(.src | index("autogroup:member")) | .dst[]
         | select(. == "autogroup:internet:*")] == []
     then "members cannot use the exit node (no autogroup:internet:* dst)" else empty end),
    (if [(.tests // [])[] | select(.src == "tag:cloud" and ((.deny // []) | length > 0))] == []
     then "no policy test denying tag:cloud → members" else empty end),
    (((.acls // [])[], (.grants // [])[])
       | select(srcs | any(. == "tag:egress")) | select(.dst != ["autogroup:internet"] and .dst != ["autogroup:internet:*"])
       | "tag:egress may reach more than the internet: \(tojson)"),
    (if [(.grants // [])[] | select(srcs == ["tag:egress"] and .dst == ["autogroup:internet"])] == []
     then "no grant tag:egress → autogroup:internet" else empty end),
    (["macbook","iphone","cloud","static-ip"] as $n | (.autoApprovers.exitNode // []) as $a
     | if ($a | index("autogroup:member")) and ($a | index("tag:cloud")) then empty
       else "autoApprovers.exitNode must cover members (macbook, iPhone, static-ip) and tag:cloud" end),
    (if [(.tests // [])[] | select(.src == "tag:egress" and ((.deny // []) | (index("user@github:22") and index("user@github:443") and index("user@github:60001"))))] == []
     then "no policy test denying tag:egress on 22/443/60001 to members" else empty end)'
}

@test "policy.hujson parses as JSON" {
  hujson "$POLICY" | jq empty
}

@test "policy.hujson keeps the network invariants" {
  run violations "$POLICY"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "violations() catches a leftover allow-all and a rule from tag:cloud" {
  bad="$BATS_TEST_TMPDIR/bad.hujson"
  hujson "$POLICY" | jq '.grants = [{"src": ["*"], "dst": ["*"], "ip": ["*"]}]
                          | .acls += [{"action": "accept", "src": ["tag:cloud"], "dst": ["*:22"]}]' > "$bad"
  run violations "$bad"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'sourced from' <<<"$output")" -eq 2 ]
}

@test "tag:egress is denied on 22, 443 and 60001 to Mac and iPhone, and may only use the internet" {
  hujson "$POLICY" | jq -e '[.tests[] | select(.src == "tag:egress" and .deny)][0].deny | (index("user@github:22") and index("user@github:443") and index("user@github:60001"))' >/dev/null
  hujson "$POLICY" | jq -e '.grants | map(select(.src == ["tag:egress"])) | length == 1 and .[0].dst == ["autogroup:internet"]' >/dev/null
  hujson "$POLICY" | jq -e '.autoApprovers.exitNode | index("autogroup:member") and index("tag:cloud")' >/dev/null
}

@test "violations() catches tag:egress reaching the tailnet" {
  bad="$BATS_TEST_TMPDIR/bad.hujson"
  hujson "$POLICY" | jq '.grants += [{"src": ["tag:egress"], "dst": ["autogroup:member"], "ip": ["*"]}]' > "$bad"
  run violations "$bad"
  [[ "$output" == *"tag:egress may reach more than the internet"* ]]
}
