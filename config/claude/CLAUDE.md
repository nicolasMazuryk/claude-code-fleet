# Global preferences
- Expert user. Be terse. Act, don't ask, for reversible changes; ask before destructive or irreversible ones.
- When you notice a repetitive step, propose turning it into a skill, slash command, or hook (give the file path + content).
- Information, tools, and best practices change fast. Before recommending a solution, approach, tool, API, check current sources rather than relying on training data. Prefer the newest established options.

# Agent rules
- In a fresh worktree, install dependencies first with the repo's package manager
  (pnpm install --frozen-lockfile / npm ci) before running anything else.
- Run only the tests affected by your change unless asked for the full suite.

# Global profile
Who I am, my goals and how to work with me, for every repo on every host. Edited on the Mac in
`~/.claude/profile/`, captured into claude-code-fleet `config/claude/profile/` by `make capture`, mirrored to cloud
by `cc-sync-settings`.
@~/.claude/profile/me.md
@~/.claude/profile/career.md
@~/.claude/profile/goals.md
@~/.claude/profile/working-style.md
@~/.claude/profile/environments.md
