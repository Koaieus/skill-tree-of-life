@tool
class_name GhostLoopBody
extends Node2D

## The shared SELF_LOOP body — "an echo chasing itself around the teardrop": a
## second [member ghost_scene] head sampled [constant GHOST_T_OFFSET] behind
## the lead's own `t`, both riding whatever [SelfLoopPath] the coordinator is
## already evaluating for the whole [Projectile] (never a second copy of that
## curve, which could only drift from the lead's own). Implements the same duck
## contract [BoltBody] does (`tint`, `_on_launch`/`_on_progress(t)`/
## `_on_arrival()`/`_on_crit(tier)`/`_on_context(entry)`, `finished`), so it
## drops straight into any wrapper's `body_scene` slot exactly like a bare
## [BoltPacket] does for the JUMP/EDGE verbs.
##
## Worn by Reverberator (#677, "an echo chasing itself") and Resonator (#678,
## "self-loops are explicitly weaponised by this spell") — one body, since the
## two only ever differed by their header comment. A spell that wants its own
## flavour reaches for [member lead_scene] / [member ghost_scene] /
## [member ghost_alpha], not for a copy of this file.
##
## The ghost is [member Node2D.top_level] — like [BoltBody]'s own trail
## segments ("trail segments live in WORLD space") — because this node's
## parent is the flying [Projectile]; a non-top_level ghost would inherit the
## PARENT's transform and sit glued to the lead instead of trailing it.
## Position is sampled from an in-memory `(t, position)` history rather than
## re-evaluating a path resource — this body never sees [ProjectilePath] or
## the raw origin/target [Vector2]s, only the `t` [Projectile] feeds it and
## its own (inherited) [member Node2D.global_position] each frame, exactly
## the inputs [BoltBody]'s own trail already samples from.

signal finished

const GHOST_T_OFFSET: float = 0.1

@export var lead_scene: PackedScene = preload("res://ui/vfx/projectile/visual/bolt_packet.tscn")
@export var ghost_scene: PackedScene = preload("res://ui/vfx/projectile/visual/bolt_packet.tscn")

## Alpha-only dimming so the ghost reads as an echo of the same head rather
## than a second identical one — `self_modulate`, never a hue change (#663
## D3) and never a material swap. [BoltBody] never touches its own
## `self_modulate` (only its trail segments'), so this channel is free.
@export_range(0.0, 1.0, 0.05) var ghost_alpha: float = 0.6

@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		_push_tint()

var _lead: Node
var _ghost: Node2D
var _history: Array = []
var _drain := VisualDrain.new(finished)


func _ready() -> void:
	if VfxEditorScene.is_edited(self):
		return
	if lead_scene != null:
		_lead = lead_scene.instantiate()
		add_child(_lead)
		_drain.track(_lead)
	if ghost_scene != null:
		_ghost = ghost_scene.instantiate() as Node2D
		if _ghost != null:
			_ghost.top_level = true
			_ghost.self_modulate = Color(1.0, 1.0, 1.0, ghost_alpha)
			add_child(_ghost)
			_drain.track(_ghost)
	# Both children live from here on; no arrival gate.
	_drain.seal()
	_push_tint()


# ---------------------------------------------------------------- duck contract


func _on_launch() -> void:
	_history.clear()
	VisualDrain.forward(_lead, &"_on_launch", [])
	VisualDrain.forward(_ghost, &"_on_launch", [])
	if _ghost != null:
		_ghost.global_position = global_position


func _on_progress(t: float) -> void:
	VisualDrain.forward(_lead, &"_on_progress", [t])
	_history.append([t, global_position])
	var ghost_t: float = t - GHOST_T_OFFSET
	if _ghost != null:
		_ghost.global_position = _sample_position(ghost_t)
	VisualDrain.forward(_ghost, &"_on_progress", [clampf(ghost_t, 0.0, 1.0)])


func _on_context(entry: Variant) -> void:
	VisualDrain.forward(_lead, &"_on_context", [entry])
	VisualDrain.forward(_ghost, &"_on_context", [entry])


func _on_crit(tier: int) -> void:
	VisualDrain.forward(_lead, &"_on_crit", [tier])
	VisualDrain.forward(_ghost, &"_on_crit", [tier])


func _on_arrival() -> void:
	if _ghost != null:
		_ghost.global_position = global_position
	VisualDrain.forward(_lead, &"_on_arrival", [])
	VisualDrain.forward(_ghost, &"_on_arrival", [])


# ------------------------------------------------------------------- internals


## Linear-interpolated position at [param target_t] off the recorded flight
## history. Clamps to the nearest recorded end rather than extrapolating —
## the ghost sits at the origin until the lead has travelled past
## [constant GHOST_T_OFFSET].
func _sample_position(target_t: float) -> Vector2:
	if _history.is_empty():
		return global_position
	if target_t <= _history[0][0]:
		return _history[0][1]
	for i in range(_history.size() - 1, 0, -1):
		var a: Array = _history[i - 1]
		var b: Array = _history[i]
		if a[0] <= target_t and target_t <= b[0]:
			var span: float = b[0] - a[0]
			var frac: float = 0.0 if span <= 0.0 else (target_t - a[0]) / span
			return (a[1] as Vector2).lerp(b[1], frac)
	return _history[_history.size() - 1][1]


func _push_tint() -> void:
	if _lead != null and "tint" in _lead:
		_lead.set("tint", tint)
	if _ghost != null and "tint" in _ghost:
		_ghost.set("tint", tint)
