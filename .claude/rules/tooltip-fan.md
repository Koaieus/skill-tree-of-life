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
progress.

**Idle is a [FanAnimation] resource, not a bool (#234).** `FanTrace.idle_anim`
and `FanPanel.idle_anim` are `null` by default (nothing in the shipped fan
idles); assigning a `.tres` opts that element in, `null` turns it off — the
resource is the swap/removal unit. Components floor `period` (~0.05s) so a
stray 0 can never spin a looped tween per-frame. Presets live in
`ui/tooltip_fan/idle/`.

**Geometry: one authored quantity per unit — where its panel sits
(`FanUnit.position`).** Trace origins are computed clock pins around 12 o'clock,
assigned in angular order around the node (never tree order); the terminus edge
is derived by `FanAnchor` for a perpendicular arrival, with `anchor_slide`
picking where along it. Pins ride the node's *screen-space* rim so the fan is
zoom-reactive while panels stay screen-constant. `FanAnchorDriver` may READ
`unit.position`, never write it — its other derived writes are only safe because
they target non-editable descendants of instanced scenes.

**One `fan.tscn`, gated per unit (#314).** There are no occupancy-class variants;
every unit mounts on every hover and `FanPanel.has_content()` is the only gate,
re-answered on every live node change (allocation, damage, core HP) and cached in
`FanUnit.participating`. Clock pins and stagger are shared out among the
*participating* units only, easing to their new slots — a suppressed panel gives
up its pin rather than holding a gap open. See docs/domain/tooltip-fan.md.

**Two-tier gate (#415): hover shows only the Roots; the FanUnit ring needs the
`ui_more_info` action (Shift) held.** `participating` still means "has content"
only — the gate is applied at the coordinator's play decisions via
`TooltipFan._should_up(unit)`, never by folding Shift into the flag (the driver's
clock spread must not care who's visible). Shift is polled in
`TooltipFan._process` (not evented) and re-runs `_refresh_content` on change;
`_on_hovered` captures the action synchronously so a held Shift at hover shows
the full fan from frame one. The action lives in project.godot; never hardcode a
keycode here. Affordance tracked in #416.
