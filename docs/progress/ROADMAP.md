# Roadmap

Phases 0–6 are built and verified; see the per-phase logs in this
directory ([phase-0](phase-0.md) … [phase-7](phase-7.md)). Details for what is left are in
[prompts/plan.md](../../prompts/plan.md).

| Phase | Scope | Status |
|---|---|---|
| 0–1 | Foundation, sanitized settings capture | done |
| 2 | Tailscale network, ACL policy with tests | done |
| 3 / 3b | Mac runtime (launchd, Remote Control servers) | done |
| 4 / 4a / 4b | Cloud runtime (systemd units, install, settings sync) | done |
| 5 | Sound relay (`agent-relay`), presence detection, ntfy pushes from both hosts | done |
| 6 | iPhone and Mac remote access (mosh, key-only sshd, ntfy subscription) | done (phone verified on both hosts 2026-10-16; push-tap re-check pending) |
| 7 | `cc-doctor` health check, extra bats coverage, disaster-recovery drills | `cc-doctor`, tests, Mac drill done; cloud + iPhone drills pending ([phase-7](phase-7.md)) |

## Limitations
- Built for one operator with one Mac, one cloud VM and one iPhone; hostnames and allowlisted repos are examples.
- Infrastructure (VM, disk, Vault) lives in a separate Terraform repo and is assumed to exist.
- Phase 6 needs manual steps on the devices (enable Remote Login on the Mac, add the iPhone key); the scripts only verify and apply what they can.
