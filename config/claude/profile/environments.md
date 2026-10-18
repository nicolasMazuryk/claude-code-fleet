# Environments: devices, names and how they connect

Authoritative detail: `~/Documents/claude-code-fleet/CLAUDE.md` and `docs/architecture.md` (cloud copy:
`~/claude-code-fleet`). No secrets or IPs here.

## Devices
| | Mac | Cloud | iPhone |
|---|---|---|---|
| Tailscale name | `macbook` | `cloud` (OCI VM `core-vm-cloud`, `tag:cloud`) | iPhone |
| OS hostname / RC device | `nicolas-macbook` | `cloud` | |
| User / home | `nicolas`, `/Users/nicolas` | `agent`, `/data/home/agent` | |
| `AGENTS_ROOT` (repos) | `~/Documents` | `/data/fleet` | |
| Agent View tmux | `agents` | `fleet` | attaches to both |
| Remote Control servers | tmux `rc`, `config/mac/repos.txt` | systemd `cc-rc@<repo>`, `config/cloud/repos.txt` | Claude app |

## How they connect
- **Tailscale** (tailnet `tailnet-example`) links all three. Members may reach `*:*`, but no rule has `src: tag:cloud`, so
  **cloud never initiates** a connection to the Mac or the iPhone. Every Mac↔cloud link is opened by the Mac.
- **Mac → cloud over SSH** (Tailscale): `fleet` (merged `claude agents --json` across both hosts, plus logs/restart/attach),
  `cc-sync-settings` (settings, CLAUDE.md, skills, hooks and this profile, mirrored from the Mac), and `agent-relay`, a
  single long-lived ssh that streams cloud hook events back to the Mac's speaker (hash-checked) and sends presence up
  every 15 s.
- **Push to the iPhone:** `agent-push` posts to ntfy only when I'm away (Mac locked/idle, or cloud's presence marker
  stale). Native Claude app pushes are off.
- **iPhone → hosts:** the Claude app via Remote Control (`mac/<repo>`, `cloud/<repo>`; outbound-only through Anthropic),
  and Moshi (mosh/SSH over Tailscale) into tmux `agents` on the Mac or `fleet` on cloud.
- **OCI edge (cloud's public services):** Cloudflare → OCI NLB → Caddy on the VM. Admin access is Tailscale only;
  break-glass is OCI Bastion (`make ssh VM=cloud` in `~/Documents/oci-free-tier-platform`). Secrets live in OCI Vault.
- **Ownership:** `oci-free-tier-platform` owns the VM, packages, the `agent` user, Tailscale and Vault;
  `claude-code-fleet` owns everything Claude Code.

## Rules of thumb
- The Mac is the source of truth for `~/.claude`. Never edit cloud's `~/.claude` by hand, and never sync cloud → Mac.
- Cloud runs agents in `auto` permission mode with sudo/docker, so treat it as less trusted than the Mac.
- macOS has bash 3.2 and BSD tools; cloud is Linux with GNU tools and bash 5.
