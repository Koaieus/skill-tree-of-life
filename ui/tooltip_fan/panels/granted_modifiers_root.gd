@tool
class_name GrantedModifiersRoot
extends Node2D

## Tooltip V2 (#226/#227) — the ROOTS: the modifier stack BELOW the node
## (Decision 1 of the swarmable spec v2). Deliberately NOT a [FanPanel]: it
## has "no containing panel" by design — a stack of small slabs, unbounded
## height, growing downward into uncontested space. So it does not go through
## [FanAnchor]'s box-edge derivation at all (Decision 4 only applies to
## panel-shaped things); its own trace (if any) is a plain vertical trunk.
##
## Still a fan-tier "component": self-animating, `play_in()`/`play_out() ->
## Tween`, a readable `progress`, driven by the coordinator ([TooltipFan])
## exactly like a [FanUnit] — [method play_in]/[method play_out] are the
## duck-typed contract the coordinator fires uniformly across everything in
## the `fan_unit` group, not just literal FanUnit instances.
##
## Content is placeholder [Label] rows here (#227 replaces this with real
## granted-modifier data) — NOT [ModSlabRow]: #221 is deleting
## `ModSlabRow.play_entry()` in parallel with this issue, so instancing it
## here would couple a stub to a component mid-refactor for no reason.

@export var placeholder_row_count: int = 3

@export_range(0.5, 1.0, 0.01) var start_scale: float = 0.9

## 0 = fully hidden (used to gate visibility only; individual rows fade via
## the shared `set_progress(t)` contract like every other content row).
var progress: float = 0.0

@onready var _rows: VBoxContainer = %Rows

var _tween: Tween = null


func _ready() -> void:
	if Engine.is_editor_hint():
		_rebuild_placeholder_rows()
		return
	_rebuild_placeholder_rows()
	progress = 0.0
	_apply_progress()
	visible = false


func _rebuild_placeholder_rows() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for i in range(placeholder_row_count):
		var l := Label.new()
		l.text = "modifier %d" % (i + 1)
		l.modulate = Color(0.7, 0.85, 0.95)
		_rows.add_child(l)


func _apply_progress() -> void:
	var eased := _ease_out(clampf(progress, 0.0, 1.0))
	scale = Vector2.ONE * lerpf(start_scale, 1.0, eased)
	var m := modulate
	m.a = eased
	modulate = m


## Self-animating IN, matching the component contract [FanTrace]/[FanPanel]
## expose post-#303: returns the [Tween] so the coordinator can `await` it.
func play_in() -> Tween:
	visible = true
	_kill_tween()
	_tween = create_tween()
	_tween.tween_method(_set_progress, progress, 1.0, 0.2) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return _tween


## Self-animating OUT. Scales the reverse duration by how far this root
## actually got (`progress`), same rule the components apply — a root that
## never rose above 0 retracts in (near) zero time rather than eyeball parity.
func play_out() -> Tween:
	_kill_tween()
	var duration: float = maxf(0.2 * progress, 0.03)
	_tween = create_tween()
	_tween.tween_method(_set_progress, progress, 0.0, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func() -> void: visible = false)
	return _tween


func enter_hidden() -> void:
	_kill_tween()
	progress = 0.0
	_apply_progress()
	visible = false


func _set_progress(t: float) -> void:
	progress = t
	_apply_progress()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


static func _ease_out(t: float) -> float:
	var inv := 1.0 - t
	return 1.0 - inv * inv * inv
