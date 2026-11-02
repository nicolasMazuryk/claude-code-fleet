---
name: allow-automation-tcc-prompts
description: "User wants Claude to click Allow on macOS Automation TCC dialogs (\"X wants access to control Y\") itself, not wait for a human"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 79ac6ef5-3190-4c6d-8385-e5f83699002f
  modified: 2026-10-31T10:27:02.661Z
---

On the Mac, macOS Automation consent dialogs ("tmux wants access to control Arc") are Claude's to approve: click **Allow**
without waiting for the user. Scope is Automation (AppleEvents) only; camera, mic, screen recording, Full Disk Access,
passwords and Touch ID stay the user's unless they say otherwise.

**Why:** user said on 2026-10-31 during the mcr-audit run: "I want you to handle and allow this kind of permissions by
yourself, without waiting for a human." Goal: no human in the loop ([[goals]]).

**How to apply:** the dialog is owned by UserNotificationCenter, pixels-only (no AX). Screenshot → compute point coords
(screenshot px / 2 on the Retina display) → `peekaboo click --at X,Y --global --foreground` under the mac-control-router
lease. The lease yields while the human is typing; retry when idle. Unverified whether macOS accepts synthetic clicks on
TCC dialogs; if it rejects them, the durable fix is a one-time pre-grant sweep (trigger each tmux→app AppleEvent once
while the user clicks Allow).
