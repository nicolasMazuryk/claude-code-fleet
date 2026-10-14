# Add a repo (Mac or cloud)

Status: scripts land in Phase 3 (Mac) and Phase 4 (cloud). **Which path applies now:** if `install.sh` and
`bin/repo-init` exist in this repo and `ssh cloud 'systemctl list-units "cc-rc@*"'` shows units, use the main steps;
otherwise (cloud still runs oci `agent@<repo>`) use the [fallback](#fallback-before-phase-4-oci-managed-agentrepo).
Phase status: [docs/progress/](../progress/).

Terms: `ac` = Mac alias that opens cloud's Agent View (`mosh cloud` → tmux `fleet`); `fleet` = Mac command listing
every session on both hosts ([spec §2.8](../spec.md)). `agent` on cloud has passwordless sudo (oci bootstrap), so the
`sudo systemctl` inside `rc-servers` never prompts.

Two independent things can be "added":
- **Agent View (`@<repo>` dispatch):** automatic for any git repo one level below `AGENTS_ROOT`
  (Mac `~/Documents`, cloud `/data/fleet`). Directory name must have no spaces.
- **Remote Control server (`<host>/<repo>` in the Claude app):** only for repos listed in
  `config/<host>/repos.txt` ([ADR 0003](../decisions/0003-repos-allowlist.md)).

## Add a repo to cloud

Prereqs (once per VM; see [cloud-rebuild](cloud-rebuild.md)): `ssh cloud true` works from the Mac; `agent` is logged
in to claude.ai and to gh (`ssh cloud 'claude auth status; gh auth status'`); Remote Control accepted once.

1. **Allowlist it** (only if you want it in the Claude app), on the Mac in this repo
   (equivalent: `repo-init --rc <repo>` run on the Mac's checkout edits the same file; on cloud `--rc` would edit the
   rsynced copy, which the next `install.sh cloud` overwrites, so always edit the list on the Mac):
   ```bash
   cd ~/Documents/cc-orchestrator
   echo '<repo>' >> config/cloud/repos.txt
   git switch -c feat/add-<repo>-cloud && git commit -am "cloud: add <repo> to RC allowlist"   # PR as usual
   ```
2. **Ship the list to cloud** (rsyncs the Mac's working tree; idempotent, safe to re-run). Deploying from the PR
   branch is fine; the human merges the PR afterwards. If the PR is rejected, revert the line and re-run.
   ```bash
   ./install.sh cloud        # or: make install-cloud
   ```
3. **Clone + prepare + trust** — needs a real terminal (TTY) because of the trust prompt:
   ```bash
   ssh -t cloud 'repo-init <repo>'
   ```
   - Clones `https://github.com/nicolasMazuryk/<repo>.git` into `/data/fleet/<repo>` if missing (gh PAT; personal
     repos under `nicolasMazuryk` only; for other hosts pass the full git URL), adds `.claude/worktrees/` to `.gitignore` and `.env`, `.env.local` to `.worktreeinclude`.
   - Opens `claude`: **accept the workspace trust prompt, then `/exit`.**
   - Runs `rc-servers`, which does `sudo systemctl enable --now cc-rc@<repo>` if `<repo>` is in the allowlist.
   - Extra files to copy into worktrees: `ssh -t cloud 'REPO_INIT_INCLUDE=".env .env.local .env.test" repo-init <repo>'`.
   - Copy any `.env` files the repo needs: `scp ~/Documents/<repo>/.env cloud:/data/fleet/<repo>/` (never commit them).
4. **Commit the setup files once** in the target repo (on cloud or the Mac) so every machine has them:
   `.gitignore`, `.worktreeinclude` — via a normal branch + PR in that repo.
5. **Verify**
   ```bash
   ssh cloud 'systemctl is-active cc-rc@<repo>'        # active
   ssh cloud 'journalctl -u cc-rc@<repo> -n 20 --no-pager'
   fleet                                               # cloud rows appear once a session exists
   ```
   - Claude app → Code lists `cloud/<repo>`; start a session → it lands in `/data/fleet/<repo>/.claude/worktrees/…`.
   - `ac` → `@<repo> hello` creates a worktree with `.env` copied.
6. Record it: update [verify.md](verify.md) only if the procedure changed.

## Add a repo to the Mac

```bash
repo-init <name | path | git-url>      # clones into ~/Documents if a URL; accept trust, /exit
# for the Claude app:
repo-init --rc <repo>                  # appends to config/mac/repos.txt, starts window rc:<repo>
cd ~/Documents/cc-orchestrator && git diff config/mac/repos.txt   # commit via branch + PR
```
Verify: `tmux list-windows -t rc` shows `<repo>`; the app lists `mac/<repo>`.

## Fallback before Phase 4 (oci-managed `agent@<repo>`)

Until `install.sh cloud` has migrated the VM, cloud repos are still managed by the oci CLI
(`~/Documents/oci/docs/runbooks/fleet-repos.md`): `make ssh VM=app`, then `fleet add <repo>`,
`fleet attach <repo>` (accept trust + Remote Control, `Ctrl-b d`). Also add the name to `config/cloud/repos.txt`
here so the Phase 4 migration keeps it.
