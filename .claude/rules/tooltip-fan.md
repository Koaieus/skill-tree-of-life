---
description: circuit-fan tooltip V2 component conventions — skin swap, progress clock contract, #215 decisions
paths:
  - "ui/tooltip_fan/**"
---

Skins are swappable packed scenes hand-placed as a child (edit which scene is
instanced, not a runtime enum), and reveal is a shared `progress(0..1)` clock
read by each component — never per-component Tweens. See
docs/domain/tooltip-fan.md for the full #215 decision record.
