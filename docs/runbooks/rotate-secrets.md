# Rotate secrets

No secret is ever in git. Vault writes use the oci repo (`cd ~/Documents/oci`); they are **human** steps.

| Secret | Where it lives | Rotate |
|---|---|---|
| ntfy topic | `~/.config/agent-push/topic` on both hosts; Vault `core-secret-ntfy-topic` | `openssl rand -hex 16 > ~/.config/agent-push/topic` (Mac, 0600) → `make secret-put NAME=core-secret-ntfy-topic FILE=~/.config/agent-push/topic` (oci) → `./install.sh cloud` → resubscribe in the ntfy iPhone app |
| Tailscale OAuth client secret (`Auth Keys: Write`, `tag:cloud`; value `tskey-client-…?ephemeral=false&preauthorized=true`) | Vault `core-secret-tailscale-authkey` | **Not rotated** (owner's decision): an OAuth client secret does not expire. Only if it leaks or the OAuth client is deleted: admin console → Settings → Trust credentials → OAuth → new client → `make secret-put NAME=core-secret-tailscale-authkey` (oci) → delete the old client. A joined node never needs it; only a node without state does (`BACKUP=none` restore, lost `/data`). See [tailscale](tailscale.md) §2 |
| GitHub PAT (fine-grained) | Vault `core-secret-github-pat` | oci `docs/runbooks/secrets-rotation.md`, then `make host-sync VM=app` |
| claude.ai login | Mac Keychain; cloud `/data/home/agent/.claude` | `claude auth logout && claude auth login` on that host (interactive) |
| Moshi key | iPhone + Mac `~/.ssh/authorized_keys` | new key in Moshi, replace the line in `authorized_keys` |
