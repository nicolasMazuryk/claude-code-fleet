# Add a repo (Mac or cloud)

Status: Mac (Phase 3) and cloud (Phase 4b, 2026-10-16: `cc-rc@<repo>` units; oci's `agent@`/`fleet` are gone).
Phase status: [docs/progress/](../progress/).

Terms: `ac` = Mac alias that opens cloud's Agent View (`mosh cloud` → tmux `fleet`); `fleet` = Mac command listing
every session on both hosts ([spec §2.8](../spec.md)). `agent` on cloud has passwordless sudo (oci bootstrap), so the
`sudo systemctl` inside `rc-servers` never prompts.

Two independent things can be "added":
- **Agent View (`@<repo>` dispatch):** automatic for any git repo one level below `AGENTS_ROOT`
  (Mac `~/code`, cloud `/data/fleet`). Directory name must have no spaces.
- **Remote Control server (`<host>/<repo>` in the Claude app):** only for repos listed in
  `config/<host>/repos.txt` ([ADR 0003](../decisions/0003-repos-allowlist.md)).

## Add a repo to cloud

Prereqs (once per VM; see [cloud-rebuild](cloud-rebuild.md)): `ssh cloud true` works from the Mac; `agent` is logged
in to claude.ai and to gh (`ssh cloud 'claude auth status; gh auth status'`); Remote Control accepted once.

1. **Allowlist it** (only if you want it in the Claude app), on the Mac in this repo
   (equivalent: `repo-init --rc <repo>` run on the Mac's checkout edits the same file; on cloud `--rc` would edit the
   rsynced copy, which the next `install.sh cloud` overwrites, so always edit the list on the Mac):
   ```bash
   cd ~/code/claude-code-fleet
   echo '<repo>' >> config/cloud/repos.txt
   git switch -c feat/add-<repo>-cloud && git commit -am "cloud: add <repo> to RC allowlist"   # PR as usual
   ```
2. **Ship the list to cloud** (rsyncs the Mac's working tree; idempotent, safe to re-run). Deploying from the PR
   branch is fine; the human merges the PR afterwards. If the PR is rejected, revert the line and re-run.
   ```bash
   ./install.sh cloud        # or: make install-cloud; clones the new repo into /data/fleet
   ```
   `rc-servers` prints `skip <repo>: workspace not trusted` until step 3.
3. **Clone + prepare + trust** — needs a real terminal (TTY) because of the trust prompt:
   ```bash
   ssh -t cloud 'repo-init <repo>'
   ```
   - Clones `https://github.com/nicolasMazuryk/<repo>.git` into `/data/fleet/<repo>` if missing (gh PAT; personal
     repos under `nicolasMazuryk` only; for other hosts pass the full git URL), adds `.claude/worktrees/` to `.gitignore` and `.env`, `.env.local` to `.worktreeinclude`.
   - Opens `claude`: **accept the workspace trust prompt, then `/exit`.**
   - Runs `rc-servers`, which does `sudo systemctl enable --now cc-rc@<repo>` if `<repo>` is in the allowlist and
     trusted (it reads `projects[dir].hasTrustDialogAccepted` in `~/.claude.json`).
   - Extra files to copy into worktrees: `ssh -t cloud 'REPO_INIT_INCLUDE=".env .env.local .env.test" repo-init <repo>'`.
   - Copy any `.env` files the repo needs: `scp ~/code/<repo>/.env cloud:/data/fleet/<repo>/` (never commit them).
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
repo-init <name | path | git-url>      # clones into ~/code if a URL; accept trust, /exit
                                       # (--no-trust skips the claude step, e.g. without a TTY)
# for the Claude app:
repo-init --rc <repo>                  # appends to config/mac/repos.txt, starts window rc:<repo>
cd ~/code/claude-code-fleet && git diff config/mac/repos.txt   # commit via branch + PR
```
Verify: `tmux list-windows -t rc` shows `<repo>`; the app lists `mac/<repo>`. A new server window first asks
`Enable Remote Control? (y/n)` until Remote Control has been accepted once on this Mac (`tmux attach -t rc:<repo>`).
`repo-init --rc` edits `config/mac/repos.txt` of the checkout in `~/.config/cc-orchestrator/config` (`CC_ORCH_DIR`).

