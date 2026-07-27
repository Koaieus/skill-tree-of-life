---
description: circuit-fan tooltip V2 component conventions — skin swap, who owns Tweens, #215 decisions
paths:
  - "ui/tooltip_fan/**"
---

Skins are swappable packed scenes hand-placed as a child (edit which scene is
instanced, not a runtime enum). **Tween ownership stops at `FanUnit`:** a leaf
component exposes `progress` / `set_progress(t)` and owns no Tween, `FanUnit`
owns the one sequential chain that drives its trace then its panel, and the
coordinator owns only a per-index start delay — there is no fan-wide clock. An
interrupt kills the running tweens and reverses from the current progress. See
docs/domain/tooltip-fan.md for the full #215/#226 decision record.
