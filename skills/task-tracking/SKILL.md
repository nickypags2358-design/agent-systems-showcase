---
name: task-tracking
description: Each session with multi-step work should use the harness task tracker (TaskCreate/TaskUpdate/TaskList) so no step is silently lost. Fires at the start of any task with 3+ steps, when new work arrives mid-turn, and before wrap-up.
---

# Task tracking — nothing gets dropped

The built-in task tracker is the live, user-visible execution board for a session. It
complements (does not replace) a durable cross-session request ledger if the project has one:
the ledger is for requests that outlive a session; the tracker is for the steps within it.

## Rules

1. At the start of any multi-step task (3+ steps), create tasks with TaskCreate — one per
   deliverable, imperative subjects.
2. New work arriving mid-turn (user message, discovered defect, spawned follow-up) gets a task
   IMMEDIATELY — before continuing the current step.
3. Mark in_progress when starting a step, completed ONLY when verified done. Blocked work stays
   in_progress with a new task describing the blocker.
4. Before wrap-up: run TaskList; every non-completed task must be either finished, or explicitly
   handed off (a ledger entry, a handover note, or an owner-routed follow-up) — never silently
   left.
5. Anything that cannot be finished in-session also goes to whatever durable ledger the project
   uses (the tracker itself is not persistent across sessions).
