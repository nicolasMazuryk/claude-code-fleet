# cc-orchestrator

Central repo for my Claude Code orchestration setup across MacBook, OCI cloud, and iPhone: configs, docs, and runbooks.

Parallel Claude Code agents on two machines, steered from a third:

- **MacBook** (`macbook`) and **cloud** (`core-vm-cloud`, Tailscale name `cloud`) each run Agent View in tmux and one
  Remote Control server per allowlisted repo.
- **iPhone** reaches both via mosh (Moshi) over Tailscale, or the Claude app (Remote Control). ntfy pushes arrive only
  when you're away from the Mac.
- Cloud sounds play on the Mac (Choo Choo) through a relay the Mac opens; cloud can never connect to the Mac.

## Where to start

| I want to… | Read |
|---|---|
| Understand the design | [docs/architecture.md](docs/architecture.md), [docs/spec.md](docs/spec.md), [docs/decisions/](docs/decisions/) |
| Build everything from nothing | [docs/runbooks/00-bootstrap-from-zero.md](docs/runbooks/00-bootstrap-from-zero.md) |
| Rebuild one device | [mac-rebuild](docs/runbooks/mac-rebuild.md) · [cloud-rebuild](docs/runbooks/cloud-rebuild.md) · [iphone-setup](docs/runbooks/iphone-setup.md) |
| Tailnet policy, cloud node, Mac rename | [tailscale](docs/runbooks/tailscale.md) |
| Add / remove a repo | [add-repo](docs/runbooks/add-repo.md) · [remove-repo](docs/runbooks/remove-repo.md) |
| Change Claude Code settings | [sync-settings](docs/runbooks/sync-settings.md) |
| Check it all works | [verify](docs/runbooks/verify.md) · [troubleshooting](docs/runbooks/troubleshooting.md) |
| Change this repo (agents) | [CLAUDE.md](CLAUDE.md) |

Status: built in phases, see [prompts/plan.md](prompts/plan.md) and [docs/progress/](docs/progress/).
Runbooks mark steps whose scripts do not exist yet with the phase that delivers them.

## Commands

```bash
make help          # every target
make lint test     # shellcheck + bats (brew install shellcheck bats-core)
```

Infrastructure (VM, disk, Tailscale package, Vault) lives in the separate `oci` repo (`~/Documents/oci`).
