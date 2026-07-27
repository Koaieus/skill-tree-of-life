---
description: circuit-fan tooltip V2 conventions — skin swap, the three composition tiers, who animates what
paths:
  - "ui/tooltip_fan/**"
---

Skins are swappable packed scenes hand-placed as a child (edit which scene is
instanced, not a runtime enum). **The fan is three tiers of composition:** a
*component* (`FanTrace`, `FanPanel`) animates itself and exposes
`play_in()`/`play_out() -> Tween` plus a readable `progress`; a *unit*
(`FanUnit`) composes one of each and does nothing but sequence them; the
*coordinator* (`TooltipFan`) composes N units and does nothing but fire them
with a per-index delay. Content rows inside a panel (`ModSlabRow`,
`PanelHeader`, `StatValueRow`, `AddonItem`) are not fan participants — they take
`set_progress(t)` and are driven by their panel. There is no fan-wide clock; an
interrupt kills the running tweens and each component reverses from its own
progress. See docs/domain/tooltip-fan.md.
