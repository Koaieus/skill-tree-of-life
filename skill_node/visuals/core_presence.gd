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
