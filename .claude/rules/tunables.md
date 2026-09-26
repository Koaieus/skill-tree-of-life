---
description: A tunable value (size, timing, ratio, threshold, count) is an exported, editor-live knob with a sensible default — never a question to the owner, never a buried const
paths:
  - "**/*.gd"
---

Picking a number nobody has an opinion on yet? Default it sensibly, `@export` it (`@export_range` when bounded) on the `@tool` node or `.tres` that owns it, give a visual one a setter that redraws in-editor, say "tentative, easy to change" — and never ask, never bury it in a `const`. Stat rates, glow and per-instance shader values have their own homes. See docs/domain/tunables.md
