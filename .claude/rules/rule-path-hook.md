---
description: The PostToolUse rule-path-hook — scoped rules fire on Bash/Write/Edit touches, once per session, fail-closed
paths:
  - ".mise/tasks/rule-path-hook"
  - ".mise/tasks/rule-path-hook-selftest"
  - ".claude/settings.json"
---

Scoped rules natively fire only on the Read tool; `rule-path-hook` makes them
fire on a Bash/Write/Edit touch too, once per rule per session (per subagent),
and must stay fail-closed (silent exit 0 on any exception; latch persisted
BEFORE printing).

**Why:** measured 2026-10-09, 95% of a main session's rule-matching file touches
go through Bash, so without the hook the scoped tier reached a quarter of its
audience. A broken JSON line on stdout here breaks every agent's next turn.

**How to apply:** any edit keeps the heredoc strip, the existing-file check, the
`agent_id` latch discriminator and the blanket `try/except`; re-run `mise run
rule-path-hook-selftest`. A rule that is now expensive is a rule to shrink, not
a hook to narrow. See docs/domain/rule-path-hook.md
