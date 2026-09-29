---
description: Design docs hold intent; the spell and core-class rosters are code; mvp_decisions.md is frozen history
paths:
  - "docs/design/**"
  - "docs/GDD.md"
  - "docs/ROADMAP.md"
---

A design doc is intent, not inventory: a spell exists iff it has a `.tres` in `attack/spell/defs/`, a core class iff it is in `entity/core/core_class_roster.tres` — anything else a doc names is an idea (`spells.md` fences its idea pool, `core_classes.md` tags each class's status). Settled calls are ADRs; `mvp_decisions.md` is a frozen log kept only so `D-N` citations resolve — never cite it as current state. See docs/design/index.md
