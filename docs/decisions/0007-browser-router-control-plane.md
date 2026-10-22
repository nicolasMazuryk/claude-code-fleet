# 0007 — browser-router: the relay carries browser leases and dispatches

- Status: accepted (2026-10-21)
- Plan: browser-router (`~/Documents/browser-router`, contracts in its `docs/contracts.md` §7)

## Context
Cloud agents need a real, logged-in browser on the Mac (headed Chrome profiles, Dia with the Claude extension, Computer
Use). The Mac must stay unreachable from cloud (invariant 4).

## Decision
- **One connection, still opened by the Mac.** `agent-relay`'s ssh to `cloud` is also the ControlMaster
  (`~/.local/state/agent-relay/cm.sock`, dir 0700). Nothing on cloud ever dials the Mac.
- **Upstream (Mac → cloud), same ssh:** a `mac-up <json>` line every beacon (`bin/browser-up`: Dia/Chrome running,
  versions, executors) which cloud writes to `~/.local/state/agent-events/mac-up` (stale after 45 s), and one-line replies
  (`lease-ready`, `lease-failed`, `release-ok`, `dispatch-ok`, `dispatch-done`) spooled by the handler and flushed each
  second. `bin/browser-relay-cloud line` validates every line; port must be 9300–9399; ids are `[A-Za-z0-9_-]`.
- **Downstream (cloud → Mac), same event stream as the hook relay:** `BrowserLease`, `BrowserRelease`, `BrowserDispatch`
  lines in `events.jsonl`. Cloud names a handler slot, never a command: the SessionStart group with matcher
  `browser-router-relay` (a source Claude Code never reports) in the Mac's `~/.claude/settings.json`, hash-checked like any
  relayed handler. `cc-sync-settings` copies that group to cloud unchanged so the sum matches.
- **CDP reverse forward.** On a lease the Mac starts headed Chrome on `~/.chrome-agent-profiles/<profile>` with
  `--remote-debugging-port=<9300–9399> --remote-debugging-address=127.0.0.1` and runs
  `ssh -S <cm.sock> -O forward -R 127.0.0.1:<p>:127.0.0.1:<p> cloud` on the ControlMaster. Cloud gets a loopback-only port;
  the forward is cancelled on release or when the ttl ends. The forward travels over the Mac-opened connection, so the
  tailnet policy still has no rule with `src: tag:cloud`.
- **Dispatch.** A `BrowserDispatch` for `mac-computer-use` runs `claude -p <task>` on the Mac, in the repo of the same
  name under `AGENTS_ROOT` (else `$HOME`), with the Mac's own permission settings; the task is one argv, never shell text.
  `dispatch-done` makes cloud run `browser-router vault finish`, freeing the global lock.
- **Vault queue.** `browser-router-vault-drain.timer` (every 3 min) starts at most one runnable job. It runs only once
  browser-router is installed. `CLAUDE_CODE_ENABLE_CFC=1` is set in cloud's settings env so `claude -p --chrome` works.
- **Install.** `install.sh cloud-local` clones browser-router to `~/.local/share/browser-router` (fast-forward, built by
  `pnpm install --frozen-lockfile && pnpm build`, linked to `~/.local/bin/browser-router`) and installs agent-browser pinned
  (`AGENT_BROWSER_VERSION`, 0.39.1) with `npm -g` + `agent-browser install`.
- **Hooks.** `~/.claude/hooks/browser-guard` (shipped by browser-router) is registered as PreToolUse for
  `mcp__claude-in-chrome__.*`, `mcp__computer-use__.*` and `Bash` (agent-browser) on the Mac; the settings sync carries it to cloud.
- **sites.yaml.** `~/.config/browser-router/sites.yaml` on the Mac is mirrored to cloud by `cc-sync-settings`.

## Consequences
- A dead relay, sleeping Mac or broken link means no `mac-up` marker: leases fail fast (exit 5), vault jobs wait.
- Cloud, which runs agents in `auto` mode, can drive a Mac Chrome profile through the leased port while the lease lasts.
  The profile is a bare name under `~/.chrome-agent-profiles`; the port range, ttl cap (4 h) and one lease per id bound it.
- Changing the Mac's relay handler needs `cc-sync-settings` (the sum changes), as for other relayed hooks.
- Verify rows 11a–11e check the relay, the lease/forward, the drain timer and the sites mirror.

## Egress gateway and the 8443 public-ingress exception
Browser Use browsers connect to our egress gateway so a site sees the same IP each time (spec §6). Browser Use publishes
no egress IP list, so the gateway cannot be restricted by source address.

- **Exception to invariant 3.** The OCI NLB listener `core-nlb` :8443 and the NSG accept `0.0.0.0/0` on TCP 8443 and
  nothing else. The NLB preserves the client address and forwards to host :8443, where `config/cloud/egress/compose.yaml`
  publishes gost (TLS, basic auth with a long random password). The OCI side is oci ADR 0006. No other ingress is opened.
- **Stack.** A `tailscale/tailscale` sidecar (node `egress`, `tag:egress`) owns a network namespace that gost and an
  nftables guard share; the router switches the sidecar's exit node. Only this stack changes route.
- **Destination hardening, two layers.** nftables in that namespace drops, for gost's dedicated uid (10001), connections
  to `0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 198.18.0.0/15,
  224.0.0.0/3`, to `::1, fc00::/7, fe80::/10, ::ffff:0:0/96`, and to any TCP port other than 80 and 443. It acts when the
  connection is opened, on the resolved IP, so hostname tricks do not help, and it leaves tailscaled's traffic alone.
  Reply packets of connections a client opened to gost (`ct direction reply`) are accepted before the drop rules: they
  do not open a connection, and their destination port is the client's ephemeral port, not 80/443. A
  gost bypass denying the same private ranges and every port except 80/443 is the second layer. Further hardening
  (an allow-list of destinations, mTLS) is not part of this design.
- **Limits and alert.** A gost limiter caps throughput (12 MB/s service, 4 MB/s per connection). An nftables counter
  on gost's uid feeds `bin/egress-bytes-alert` (every 10 min); past `EGRESS_DAILY_BYTES` (5 GiB) it pushes once a day
  through `agent-push`.
- **Fail closed.** gost starts only when the guard reports healthy (table loaded); the guard re-checks every 10 s.
- **Reply routing.** Replies to clients that arrived on the published port must leave through `eth0`, while gost's own
  outbound traffic follows the exit node. Connections arriving on `eth0:8443` get ct mark 0x2, their packets fwmark 0x2,
  and `ip rule fwmark 0x2/0x2 lookup main priority 5100` (above tailscale's rules) routes them directly.
- **Secrets.** The proxy password sits in OCI Vault (`core-secret-egress-proxy-password`) but the cloud dynamic group is
  denied that secret (oci IAM option B): `./install.sh cloud` delivers it from the Mac, Keychain `cc-egress-proxy-password`
  → `cloud:~/.config/egress/gost-auth` (0400, uid 10001) over the Mac-opened ssh via stdin (`bin/egress-secrets-push`).
  The Browser Use key (`core-secret-browser-use-api-key`) stays readable by cloud: the cloud brain calls Browser Use.
  Nothing on cloud ever dials the Mac; the new node `egress` has `tag:egress`, whose only permission is the internet
  through an exit node, and the policy tests keep it denied on 22/443/60001 to the Mac and iPhone.
- **TLS certificate.** The gateway serves a publicly trusted certificate for `egress.mazuryktech.com` (DNS-only record,
  oci ADR 0006), so Browser Use verifies it (`ignoreCertErrors: false`). The Mac issues and renews it (`bin/egress-cert-renew`,
  lego, ACME DNS-01 through Cloudflare with a Keychain token scoped to DNS edit on that zone) and pushes `cert.pem` and
  `key.pem` over the Mac-opened ssh; cloud holds no DNS-edit power and no ACME account. A key on cloud can only impersonate the
  gateway, which is already exposed there. Renewal follows the CA's ARI hint, falling back to 1/3 of the lifetime left, and
  cloud alerts through `agent-push` when less than 1/3 is left. DNS-01 is used because port 80 and 443 on the VM are not
  available to the Mac and the NLB forwards only 8443.
- **Public ingress is not otherwise reduced:** Cloudflare is not in front of 8443 (raw TCP), so the password and the
  limiter are the controls.
