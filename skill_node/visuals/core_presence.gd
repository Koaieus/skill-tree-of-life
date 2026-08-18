@tool
class_name CorePresence
extends Node2D
## Groups the core-only presence visuals (the [CoreHalos] gimbal + the
## [CoreSigilBloom] glow) so a core move animates them as one unit instead of
## the old lone star `CoreMarker` (#128, docs/domain/skillnode-emblem.md).
##
## Decoupled by an optional per-child hook contract, duck-typed like the
## family's existing get_node_effects()/composite `_children` fan-out, rather
## than this script hardcoding CoreHalos/CoreSigilBloom by name or type:
##   `on_core_travel_start(local_offset: Vector2, duration: float) -> void`
##   `on_core_travel_arrived() -> void`
## Every child that implements either gets called; children that don't are
## skipped. This is what lets [method glide_from] serve BOTH the live in-scene
## CorePresence (nested under NodeVisualsComposite/ShaderStack) and a second,
## standalone instance used as the core-move drag ghost — CorePresence itself
## never needs to change for either consumer, or for a future third
## core-presence register.
##
## The two registers currently travel differently, per the locked #128 design:
## - [CoreHalos] physically GLIDES on `on_core_travel_start` — the same
##   offset->zero tween that used to move the star marker.
## - [CoreSigilBloom] does NOT glide. `on_core_travel_start` hides it;
##   `on_core_travel_arrived` bursts it back in — so the bloom reads as
##   extinguishing at the old node and reigniting at the new one, in lockstep
##   with the halo's arrival, rather than visually traveling along the edge.
##
## Nested under NodeVisualsComposite/ShaderStack (same spot CoreHalos already
## lived) rather than a composite-level sibling: `sensed` hides the whole
## ShaderStack in one move, so a fogged/enemy core needs no separate gate here
## (see .claude/rules/skill-node-visuals.md's sensed section). Both children
## stay at relative z_index 0 so CoreHalos' own GimbalBack relative-z offset
## (see skill-node-visuals.md) is unaffected by this extra nesting level.

## The [CoreHalos] style as `core_presence.tscn` authored it (today: GIMBAL),
## cached the first time [method set_halo_style] overrides it — so a later
## `style == -1` call can hand it BACK rather than merely declining to touch
## the (already-overridden) live value. `-1` sentinel for "not cached yet";
## every real [CoreHalos.CoreHaloStyle] value is `>= 0`, so it can't collide
## with a legitimately-authored `NONE` (0).
var _authored_halo_style: int = -1


## Overrides [member CoreHalos.halo_style] on the [CoreHalos] child. `style ==
## -1` restores whatever `core_presence.tscn` authored (cached in [member
## _authored_halo_style] on first override) — a genuine restore, not merely a
## no-op, so a caller that overrides and later clears the override (a
## removable blocker, #478, going COG-while-blocked → Default-once-cleared)
## gets its normal halo back rather than staying stuck on the override. See
## [member SkillNode.core_halo_style]'s docstring for the sentinel and the
## perf motivation (COG instead of the expensive GIMBAL while blocked).
##
## EXPLICIT — a named child lookup, not duck-typed like [method glide_from]'s
## `on_core_travel_start`/`on_core_travel_arrived` hooks above. Those hooks
## exist so an arbitrary FUTURE core-presence register (a third child besides
## CoreHalos/CoreSigilBloom) opts in for free without this script changing.
## `halo_style` is not a generic per-child capability in that sense — it's a
## property that belongs to CoreHalos specifically, so pretending every child
## might have one via `has_method`/duck typing would just hide a real
## dependency behind a weaker contract for no benefit.
func set_halo_style(style: int) -> void:
	var halos := get_node_or_null(^"CoreHalos")
	if halos == null:
		return
	if style < 0:
		if _authored_halo_style >= 0:
			halos.halo_style = _authored_halo_style
		return
	if _authored_halo_style < 0:
		_authored_halo_style = halos.halo_style
	halos.halo_style = style


## Slides children in from `local_offset` (this node's position the instant
## before a core move commits, expressed relative to this node — the caller
## already computed the world delta) — see the hook contract above. No-op
## guard against a degenerate (zero) offset is the caller's job, same as the
## old play_core_slide_from.
func glide_from(local_offset: Vector2, duration: float = 0.25) -> void:
	for child in get_children():
		if child.has_method(&"on_core_travel_start"):
			child.on_core_travel_start(local_offset, duration)
	var timer := create_tween()
	timer.tween_interval(duration)
	timer.tween_callback(_notify_arrived)


func _notify_arrived() -> void:
	for child in get_children():
		if child.has_method(&"on_core_travel_arrived"):
			child.on_core_travel_arrived()
