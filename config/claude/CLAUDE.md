# Global preferences
- Expert user. Be terse. Act, don't ask, for reversible changes; ask before destructive or irreversible ones.
- When you notice a repetitive step, propose turning it into a skill, slash command, hook, etc (give the file path + content).
- Information, tools, and best practices change fast. Before recommending a solution, approach, tool, API, check current sources rather than relying on training data. Prefer the newest established options.

# Agent rules
- In a fresh worktree, install dependencies first with the repo's package manager (pnpm install --frozen-lockfile / npm ci) before running anything else.
- In a background job, call EnterWorktree before the first write; never `cd` into the shared checkout afterwards.
- Run `git` from the cwd, not `git -C <computed path>` (the isolation guard rejects commands it can't verify).
- Write files with Edit/Write, not `sed -i` or `cat > file <<EOF`; pass long commit messages with `git commit -F <file>`.
- Wait with Monitor or `run_in_background`, never `sleep`.

# Global profile
Who I am, my goals and how to work with me, for every repo.
@~/.claude/profile/me.md
@~/.claude/profile/goals.md
@~/.claude/profile/working-style.md
@~/.claude/profile/environments.md

# Browser
- Before any browser or web-app task (sites, logins, forms, scraping, accounts), use the `browser-router` skill (`~/.claude/skills/browser-router`); never pick a browser tool directly.
