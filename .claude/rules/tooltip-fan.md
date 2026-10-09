---
description: circuit-fan tooltip V2 conventions — skin swap, the three composition tiers, who animates what
paths:
  - "ui/tooltip_fan/**"
---

Composition, geometry, gating and the serialization invariant:
docs/domain/tooltip-fan.md. The gotchas:

- **`FanAnchorDriver` may READ `unit.position`, never write it.** The unit's
  position is the authored rest in `fan.tscn`; the driver's other derived writes
  are safe only because they target non-editable descendants of instanced scenes.
- **`FanUnit.participating` means "has content" and nothing else.** The Shift gate
  is applied at the coordinator's play decisions, `TooltipFan._should_up(unit)`;
  folding Shift into the flag would make the driver's clock spread depend on
  who is visible.
- **Shift is polled in `TooltipFan._process`, not evented**, and `_on_hovered`
  captures it synchronously so a held Shift at hover shows the full fan from
  frame one.
- **Never hardcode a keycode:** the gate is the `ui_more_info` InputMap action.
- **Idle is a `FanAnimation` resource** (`idle_anim`, `null` = off). Components
  floor `period` (~0.05 s) so a stray 0 cannot spin a looped tween per frame.
- **No fan-wide clock.** Components animate themselves and interrupt = kill and
  reverse from each one's own `progress`; `FanUnit` only sequences.
