---
name: prov-cli-on-server
description: How to run provisioning/one-shot Node CLIs on the prod server (no node on host — docker only)
metadata:
  type: project
---

The Hetzner prod host `178.104.134.61` (`ssh -i ~/.ssh/nicolas nicolas@...`) has **no node/npm on the host** — everything runs via the `arbinet:latest` Docker image (built from `Dockerfile`: compiled `dist/` + prod-only `node_modules`; no `src`, no `tsx`, no `live-configs/`).

To run a provisioning CLI (e.g. `normalize-keys`) on the server, run the **compiled** JS in a container, mounting `.env` (for dotenv master creds) and a **directory** holding the registry (a single-file mount breaks `saveRegistry`'s tmp+rename):

```
mkdir -p /tmp/prov && cp /opt/arbinet/repo/live-configs/registry.yaml /tmp/prov/
docker run --rm \
  -v /opt/arbinet/.env:/app/.env:ro \
  -v /tmp/prov:/data:rw \
  arbinet:latest \
  node dist/execution/provisioning/cli/normalize-keys.js --exchange <ex> --registry /data/registry.yaml
```

Master creds live in `/opt/arbinet/.env` as `<EX>_API_KEY/SECRET/PASSPHRASE` (loaded by `loadMasterCredentials` fallback). Repo checkout is `/opt/arbinet/repo` (real git clone, pulls `repo_branch=main`). Master keys are IP-locked to `.61`, so all provisioning MUST run on the server. OKX `modifyApikey` rate-limits hard (`50011`) with the CLI's no-delay loop — space calls ~3s. See [[binance-subkey-ip-manual]].
