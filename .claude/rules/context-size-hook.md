---
description: The PostToolUse context-size-hook — subagent payload quirks, tail-read/latch design, fail-closed contract
paths:
  - ".mise/tasks/context-size-hook"
  - ".mise/tasks/context-size-hook-selftest"
  - ".claude/settings.json"
---

A subagent's `PostToolUse` payload carries the **parent's** `session_id` /
`transcript_path`, not its own — presence of `agent_id` is the only
discriminator, and the subagent's real transcript must be derived
(`dirname(transcript_path)/session_id/subagents/agent-<agent_id>.jsonl`), never
hardcoded or read from `transcript_path` directly.

**Why:** trusting `transcript_path` for a subagent call measures the
orchestrator's context on every drone's tool call and latches the whole fleet
against one shared key — since drones are this hook's entire target
population, that bug makes the hook silently report nothing useful while
looking like it works.

**How to apply:** any edit to `context-size-hook` must preserve: (1) the
`agent_id`-presence discriminator, (2) tail-reading the transcript (last 64KB)
rather than parsing the whole file — it runs after every tool call in every
session, (3) latching on `session_id` + (`agent_id` or `"main"`), and (4) the
blanket fail-closed `try/except` in `__main__` — a broken JSON contract on
stdout here breaks every agent's next turn, not just this one's. Re-run
`mise run context-size-hook-selftest` after any change. Full design and the
verified payload trail: see docs/domain/context-size-hook.md.
