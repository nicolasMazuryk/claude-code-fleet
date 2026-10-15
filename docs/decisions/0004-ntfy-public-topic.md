# 0004 — Pushes via public ntfy.sh with an unguessable topic

- Status: accepted (2026-10, confirmed with user)
- Plan: Phases 3 and 5

## Context
iPhone alerts must fire only when the user is away from the Mac, for sessions on both hosts. The Claude app's own push
only knows terminal focus. Self-hosting ntfy would need a public endpoint, which the OCI invariants forbid.

## Decision
- Use `https://ntfy.sh` with a random topic (`openssl rand -hex 16`).
- The topic lives in `~/.config/agent-push/topic` (mode 0600) on each host, **never in git**, and is backed up in
  OCI Vault as `core-secret-ntfy-topic` so a rebuild can recover it (`install.sh` fetches it from Vault when the
  local file is missing; otherwise it creates one and the human stores it with `make secret-put`).
- Native app pushes are disabled (`agentPushNotifEnabled: false`, `inputNeededNotifEnabled: false`).
- Push bodies are truncated to 140 chars of the session message.

## Consequences
- Anyone who learns the topic can read/send pushes: rotate it (runbook `rotate-secrets.md`) if leaked.
- `NTFY_SERVER` can point to another server later without code changes.
