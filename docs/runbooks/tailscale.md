# Tailscale: tailnet policy, cloud node, Mac rename

Phase 2. Design: [ADR 0001](../decisions/0001-tailscale-on-oci.md). Policy: `config/tailscale/policy.hujson`.
The cloud side (install, join, mosh rule) is in the oci repo: `host/cloud/bootstrap.sh` → `setup_tailscale` and
`allow_udp_on_iface` (oci runbook `access-ssh.md`). `[H]` = human-only step. Every step is safe to re-run.

## Facts
- Tailnet `example.github`, MagicDNS suffix `tailnet-example.ts.net`, login `user@github`.
- Mac node `macbook` (was `nicolas-macbook`), member. Exit node `static-ip` (Hetzner, member, `~/Documents/static-ip`).
- Cloud node `cloud` = `core-vm-cloud` (OS hostname `cloud` too; was `app` until 2026-10-16), `tag:cloud`, Tailscale SSH on (users `agent`, `ubuntu`), `--accept-dns=false`
  (the VM keeps OCI's resolver). Its state is on `/data/core/tailscale`, so a restore from backup rejoins as the same node.
- Join credential: Vault `core-secret-tailscale-authkey` holds a **Tailscale OAuth client secret** (scope
  `Auth Keys: Write`, tag `tag:cloud`), stored as `tskey-client-…?ephemeral=false&preauthorized=true`. Unlike an auth
  key it **does not expire**, so it is never rotated or refreshed (owner's decision, 2026-10). `tailscale up` mints a
  non-ephemeral, pre-approved `tag:cloud` node key from it. Bootstrap reads it only when the node has no state, and
  passes it as `--auth-key=file:…` (never on argv). The original 90-day auth key was revoked.
- mosh: iptables `-i tailscale0 -p udp --dport 60000:61000 -j ACCEPT` before the image's REJECT, live and in
  `/etc/iptables/rules.v4`. Tailscale SSH needs no port. No NSG change, no public IP.

## 1. `[H]` Apply the tailnet policy (before the cloud node joins)

1. Admin console → **Access controls** → JSON editor. Copy the current policy to a scratch file outside git.
2. Merge. `policy.hujson` assumes the tailnet default: an allow-all rule plus the `autogroup:self` ssh check rule.
   - **Remove** the default allow-all (`"acls": [{"action": "accept", "src": ["*"], "dst": ["*:*"]}]` or
     `"grants": [{"src": ["*"], "dst": ["*"], "ip": ["*"]}]`). It would let `tag:cloud` reach the Mac.
   - **Keep** anything else that is in the live policy and not in the file: `nodeAttrs`, `autoApprovers` (exit node),
     `groups`, `hosts`, other tags or ssh rules. Add it to `policy.hujson` too, in a commit, so the file stays "as applied".
   - Nothing new may have `src` `tag:cloud` or `*`. `make test` checks this (`tests/tailscale-policy.bats`).
3. The file uses the placeholder login `user@github`; substitute the real login when pasting:
   `sed "s/user@github/<login>/g" config/tailscale/policy.hujson | pbcopy`. Policy tests cannot target autogroups
   (`autogroup:internet`), so the `tag:egress` → internet grant is checked by `tests/tailscale-policy.bats` only.
4. Paste the merged file → **Save**. Tailscale runs the `tests`/`sshTests` blocks on save and rejects the policy if
   `tag:cloud` could reach a member device, or members could not SSH to `tag:cloud` as `agent`/`ubuntu`.
5. Check that the exit node still works on the Mac: `curl -s https://ifconfig.me` → the `static-ip` address.

## 2. `[H]` Create the OAuth client and store its secret in Vault (one time; never rotated)

1. Admin console → **Settings → Trust credentials → OAuth → Generate OAuth client**: scope **Auth Keys: Write**,
   tag **`tag:cloud`**. Copy the client secret (`tskey-client-…`); it is shown once.
2. Append the join options to it, so the secret value is
   `tskey-client-…?ephemeral=false&preauthorized=true` (a non-ephemeral, pre-approved node that survives reboots).
3. In `~/Documents/oci-free-tier-platform`, from a real terminal: `make secret-put NAME=core-secret-tailscale-authkey` (hidden prompt).
   No TTY: `f=$(mktemp) && pbpaste > "$f" && make secret-put NAME=core-secret-tailscale-authkey FILE="$f"; rm -f "$f"; printf '' | pbcopy`.

## 3. `[H]` Ship the oci bootstrap to the VM

The oci change must be on the checkout you sync from (merge its PR, then `git -C ~/Documents/oci-free-tier-platform pull`).
```bash
cd ~/Documents/oci-free-tier-platform && make host-sync VM=cloud
scripts/ssh.sh cloud 'grep -iE "tailscale|tailnet" /var/log/core-bootstrap.log | tail -5; tailscale status; sudo iptables -S INPUT | grep 60000'
```
Expected: `tailscale joined as cloud.tailnet-example.ts.net.`; `tailscale status` lists `cloud` and `macbook`; the
`tailscale0` rule is present. Re-running `host-sync` logs `tailscale up as …` and changes nothing.
(Since oci-infra PR #2, `make ssh VM=cloud CMD='a; b'` runs both commands on the VM. Before it, the part after `;` ran on the Mac.)

## 4. `[H]` Rename the Mac node to `macbook`

Admin console → Machines → `nicolas-macbook` → **Edit machine name** → `macbook` (turn off auto-generate). The
CLI alternative (`tailscale set --hostname=macbook`) only applies if the name was never edited in the console.
The exit node is selected by node ID, so it keeps working. Check: `tailscale status --self --peers=false` shows `macbook`,
and `curl -s https://ifconfig.me` still returns the `static-ip` address.

## 5. Verify (from the Mac)

Until Phase 3 installs `Host cloud` (`User agent`) in `~/.ssh/config`, give the user explicitly.
```bash
ssh -o StrictHostKeyChecking=accept-new agent@cloud true; echo $?            # 0  (Tailscale SSH, no key)
script -q /dev/null sh -c 'stty rows 40 cols 120; mosh agent@cloud -- sh -c "sleep 2; echo MOSH_OK"'`  # MOSH_OK
tailscale ping --icmp -c 2 cloud                                             # pong (Mac → cloud allowed)
ssh agent@cloud 'sudo tailscale ping --icmp -c 2 --timeout 3s macbook'       # no pong: the ACL drops cloud → Mac
cd ~/Documents/oci-free-tier-platform && make ssh VM=cloud CMD=true; echo $?                      # 0  (Bastion break-glass still works)
```
mosh needs a terminal size: without a TTY (scripts, Claude Code's `!` shell) plain `mosh … -- true` fails with
`Error: vector`, hence the `script`/`stty` wrapper. In a real terminal `mosh cloud` is enough. The Mac firewall must
allow `mosh-client` ([mac-rebuild](mac-rebuild.md) step 2a).
Plain `tailscale ping` (disco, no `--icmp`) from cloud may still get a pong: disco runs below the packet filter and
does not mean cloud can open a connection. The ACL is proven by `--icmp` and by the policy `tests` that Tailscale
evaluated on save. These are rows 1–1d in [verify](verify.md).

## Rebuild notes
- Restore from backup: the state on `/data` comes back, so the node is the same `cloud` and needs no key.
- `make restore BACKUP=none` or a lost `/data`: delete the old `cloud` machine in the admin console first (or the new
  node becomes `cloud-1`), and make sure Vault holds the OAuth client secret (step 2; it does not expire, but check the OAuth client still exists
  in the admin console).
- The Mac (fresh install): log in to the Tailscale app, then step 4.

## 6. `[H]` Egress node, exit nodes (browser-router)
`policy.hujson` adds `tag:egress` (tagOwners), `autoApprovers.exitNode` (members: macbook, iPhone, static-ip; `tag:cloud`) and the
grant `tag:egress → autogroup:internet`. `tag:egress` has no other permission; the policy tests keep both `tag:cloud` and
`tag:egress` denied on 22/443/60001 to the Mac and iPhone (`tests/tailscale-policy.bats` checks the file; Tailscale re-checks on save).
1. Merge and apply as in §1 (keep anything live that is not in the file).
2. Admin console → Settings → Trust credentials → OAuth (Auth Keys: Write, tag `tag:egress`) or a one-off auth key tagged
   `tag:egress`; store it in the Mac Keychain as `cc-egress-ts-authkey` ([browser.md](browser.md) egress section).
3. Exit nodes: macbook `tailscale set --advertise-exit-node`; iPhone Tailscale app → Exit Node → **Run as Exit Node**; cloud is
   advertised by the oci bootstrap; static-ip already is. Auto-approval covers all four.
4. Switching: `browser-router exit-node use <node|none> [--for self|egress]` replaces the `staticipup`/`staticipdown` aliases
   (remove them from `~/.zshrc`; `config/mac/zshrc.captured` no longer carries them). A node acting as an exit node cannot use one.
5. Check: `ssh cloud docker exec egress-tailscale-1 tailscale status` lists the node `egress` with the tag; `tailscale ping --icmp`
   from it to `macbook` gets no pong.
