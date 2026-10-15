# bin/

Scripts symlinked into `~/.local/bin` on both hosts by `install.sh` (editing them here changes what runs).
Planned (see `prompts/plan.md` and `docs/spec.md`): `agent-env agents-loop rc-serve rc-servers repo-init
agent-present cc-relay-hook fleet cc-sync-settings agent-relay cc-capture cc-doctor cc-orchestrator-start`.

Rules: `#!/usr/bin/env bash`, idempotent, shellcheck-clean (`make lint`), bash 3.2 compatible if it runs on the Mac.
