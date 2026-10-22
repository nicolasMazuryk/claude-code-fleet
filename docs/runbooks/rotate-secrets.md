# Rotate secrets

No secret is ever in git. Vault writes use the oci repo (`cd ~/Documents/oci-free-tier-platform`); they are **human** steps.

| Secret | Where it lives | Rotate |
|---|---|---|
| ntfy topic | `~/.config/agent-push/topic` on both hosts; Vault `core-secret-ntfy-topic` | `openssl rand -hex 16 > ~/.config/agent-push/topic` (Mac, 0600) → `make secret-put NAME=core-secret-ntfy-topic FILE=~/.config/agent-push/topic` (oci) → `./install.sh cloud` → resubscribe in the ntfy iPhone app |
| Tailscale OAuth client secret (`Auth Keys: Write`, `tag:cloud`; value `tskey-client-…?ephemeral=false&preauthorized=true`) | Vault `core-secret-tailscale-authkey` | **Not rotated** (owner's decision): an OAuth client secret does not expire. Only if it leaks or the OAuth client is deleted: admin console → Settings → Trust credentials → OAuth → new client → `make secret-put NAME=core-secret-tailscale-authkey` (oci) → delete the old client. A joined node never needs it; only a node without state does (`BACKUP=none` restore, lost `/data`). See [tailscale](tailscale.md) §2 |
| Egress proxy password | Vault `core-secret-egress-proxy-password` (cloud cannot read it: IAM option B) and Mac Keychain `cc-egress-proxy-password`; delivered to `cloud:~/.config/egress/gost-auth` | new random value → `make secret-put NAME=core-secret-egress-proxy-password` (oci) → `security add-generic-password -U -s cc-egress-proxy-password -a "$USER" -w` → `./install.sh cloud` (delivers via `bin/egress-secrets-push`) → `ssh cloud sudo systemctl restart cc-egress` → update the Browser Use proxy credentials (browser-router) |
| Browser Use API key | Vault `core-secret-browser-use-api-key` (cloud can read it) | oci `docs/runbooks/secrets-rotation.md`, then `make host-sync VM=cloud` |
| Egress tailscale join key (`tag:egress`) | Mac Keychain `cc-egress-ts-authkey` → `cloud:~/.config/egress/ts-authkey` | only needed for the first join of node `egress` (state persists); then `./install.sh cloud` and empty the file if desired |
| GitHub PAT (fine-grained) | Vault `core-secret-github-pat` | oci `docs/runbooks/secrets-rotation.md`, then `make host-sync VM=cloud` |
| claude.ai login | Mac Keychain; cloud `/data/home/agent/.claude` | `claude auth logout && claude auth login` on that host (interactive) |
| Moshi key | iPhone + Mac `~/.ssh/authorized_keys` | new key in Moshi, replace the line in `authorized_keys` |
