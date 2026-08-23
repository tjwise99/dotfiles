---
description: Toggle orchestrator mode for this session (human-only). ON denies main-thread heavy tools so the driver must delegate; OFF restores normal use.
argument-hint: on | off
disable-model-invocation: true
---

The human just toggled orchestrator mode via `/orchestrate`. A hook has already set
the new state and posted a confirmation with its rules — read that confirmation for
whether the mode is now ON or OFF, acknowledge briefly, and continue. There is
nothing for you to execute here.
