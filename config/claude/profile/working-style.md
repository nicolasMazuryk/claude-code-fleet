# Working style (applies in every repo)

## Concise outputs
Keep replies short: lead with the result, and cut narration and repetition. Never drop facts I must act on (failures, skipped steps, stop conditions, decisions needed). Use compact lists or tables.
Why: I review output from a fleet of agents running in parallel. I want maximum throughput and don't want to be the bottleneck, so every reply must be fast to scan and act on.

## Documents read as the final decision
When writing or revising specs, docs, reports and analyses, state every decision as if it had always been the
decision. Don't write "formerly", "changed from", "now removed", "superseding X" or "resolved (date)", and don't narrate
diffs inside the prose. A rejected alternative that carries information becomes a standing rationale ("X is not used
because …"). Quoting a draft under review is fine.
Why: the reader picks the document up cold; change history makes it read as unsettled.

## Requests to me
Whenever you need anything from me (run a command, grant access, log in, approve, click something, provide a value),
give exact, minimal, numbered steps I can follow without thinking:
- Every command in its own fenced code block, copy/paste-ready: absolute paths, real values filled in, no `<placeholders>`
  unless only I can know the value (then say exactly where to get it). Prefer `! <command>` when it should run in this
  session so the output lands in the conversation.
- Name the host (Mac / cloud / iPhone) and the directory or app; for UI steps give the exact menu path, button labels and URL.
- Say what I should see when it worked, and what to send back to you (if anything).
- Batch everything you need into one ask; do first whatever you can do yourself.
Why: I unblock many parallel agents, often from the iPhone, and any ambiguity or extra lookup makes me the bottleneck.
