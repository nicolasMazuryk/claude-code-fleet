# Bootstrap from zero (all three devices)

Order matters: network first, then the Mac (source of truth), then cloud, then the phone.
Each step links to the runbook that has the details. `[H]` = human-only step.

| # | Step | Runbook | Done when |
|---|---|---|---|
| 1 | Clone this repo to `~/Documents/cc-orchestrator` on the Mac (`gh repo clone nicolasMazuryk/cc-orchestrator`) | — | `make help` works |
| 2 | `[H]` Tailscale on the Mac; rename node to `macbook` | [mac-rebuild](mac-rebuild.md) | `tailscale status` shows `macbook` |
| 3 | `[H]` Apply `config/tailscale/policy.hujson` in the admin console (keeps exit node `static-ip`) | [cloud-rebuild](cloud-rebuild.md) | policy saved |
| 4 | `[H]` Vault secrets `core-secret-tailscale-authkey`, `core-secret-ntfy-topic` (oci `make secret-put`) | [rotate-secrets](rotate-secrets.md) | `oci secrets` lists them |
| 5 | VM up with Tailscale + mosh rule (oci repo: `make restore` or first deploy, then `make host-sync VM=app`) | [cloud-rebuild](cloud-rebuild.md) | `ssh cloud true` from the Mac |
| 6 | Mac runtime: `brew install tmux mosh shellcheck bats-core && ./install.sh mac` | [mac-rebuild](mac-rebuild.md) | `am` shows Agent View |
| 7 | `[H]` Mac: accept Remote Control once, Full Disk Access for tmux, `repo-init` allowlisted repos | [mac-rebuild](mac-rebuild.md) | app lists `mac/<repo>` |
| 8 | Cloud runtime: `./install.sh cloud` | [cloud-rebuild](cloud-rebuild.md) | `ac` shows Agent View; sync reports 4 relayed |
| 9 | `[H]` Cloud: `claude auth login`, accept Remote Control, `repo-init` allowlisted repos | [add-repo](add-repo.md) | app lists `cloud/<repo>` |
| 10 | `[H]` iPhone: Tailscale, Moshi hosts, ntfy, Claude app | [iphone-setup](iphone-setup.md) | dispatch from the phone on both hosts |
| 11 | Mac remote access for the phone (Remote Login, keys-only sshd, mosh firewall, pmset) | [mac-rebuild](mac-rebuild.md) | `mosh macbook` from the phone |
| 12 | Run every check | [verify](verify.md) | `make doctor` green on both hosts |
