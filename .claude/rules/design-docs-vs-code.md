---
description: docs/design holds what could be; docs/domain holds what is; ADRs hold what was — rosters are code
paths:
  - "docs/design/**"
  - "docs/domain/**"
  - "docs/GDD.md"
  - "docs/ROADMAP.md"
---

`docs/design/` is what *could* be — never inventory and never history (a superseded or contradicted passage is deleted, not annotated); `docs/domain/` is what *is*; history lives only in `docs/adr/` (incl. the pre-ADR `legacy-mvp-decisions.md` D-N log). A spell exists iff it has a `.tres` in `attack/spell/defs/`, a core class iff it is in `entity/core/core_class_roster.tres`. A drone treats a design doc as spec only when its `Ready` issue cites it; otherwise the issue, `docs/domain` and code are the truth. See docs/design/index.md
