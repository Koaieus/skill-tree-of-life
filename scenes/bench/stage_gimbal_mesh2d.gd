extends Node2D
## The [code]mesh2d[/code] stage-gimbal substrate (#1075, shape B): takes one
## slot from the level's lazily created [GimbalBatch] and exposes the
## three-property contract every row of [code]IdleTurnProbe[/code]'s substrate
## table shares ([code]ring_count[/code], [code]tint[/code],
## [code]base_radius[/code]). The probe sets the properties BEFORE add_child
## and `global_position` AFTER it, so the slot is pushed on transform change.
##
## Bench-only env knobs (the bench's arg parser is #1073's, not this unit's):
##   GIMBAL_MESH2D_STYLE = glass (default) | glyph
##   GIMBAL_MESH2D_PAD   = N extra instances placed far off screen, once per
##                         batch — the "full batch, most instances off screen"
##                         culling measurement.

## Ring radius = the SkillNode radius x this, matching CoreHalos' live halo_scale.
const HALO_SCALE := 1.8

@export_range(1, 5, 1) var ring_count: int = 5:
	set(value):
		ring_count = value
		_push_params()

@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		_push_params()

@export var base_radius: float = 32.0:
	set(value):
		base_radius = value
		_push_transform()

var _batch: GimbalBatch
var _slot: int = -1
var _pad_owners: Array = []


func _ready() -> void:
	set_notify_transform(true)
	_batch = GimbalBatch.ensure_for(self)
	_slot = _batch.acquire(self)
	_push_params()
	_push_transform()
	_pad_batch()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_push_transform()
	elif what == NOTIFICATION_EXIT_TREE and _batch != null:
		_batch.release(self)
		for o in _pad_owners:
			_batch.release(o)
		_pad_owners.clear()
		_slot = -1


func _style() -> GimbalBatch.Style:
	return GimbalBatch.Style.SOLID_GLYPH if OS.get_environment("GIMBAL_MESH2D_STYLE") == "glyph" \
			else GimbalBatch.Style.HOLO_GLASS


func _push_params() -> void:
	if _slot == -1:
		return
	_batch.set_slot_params(_slot, tint, ring_count, _style(), randf() * TAU, 1.0)


func _push_transform() -> void:
	if _slot == -1:
		return
	_batch.set_slot_transform(_slot, global_position, base_radius * HALO_SCALE)


func _pad_batch() -> void:
	var pad := int(OS.get_environment("GIMBAL_MESH2D_PAD"))
	if pad <= 0 or _batch.has_meta(&"padded"):
		return
	_batch.set_meta(&"padded", true)
	for i in pad:
		var o := RefCounted.new()
		_pad_owners.append(o)
		var slot := _batch.acquire(o)
		var ang := TAU * float(i) / float(pad)
		var pos := global_position + Vector2.from_angle(ang) * (8000.0 + 4000.0 * float(i % 3))
		_batch.set_slot_params(slot, tint, ring_count, _style(), float(i), 1.0)
		_batch.set_slot_transform(slot, pos, base_radius * HALO_SCALE)
	print("stage    : mesh2d padded with %d off-screen instances (batch live=%d)" % [pad, _batch.live_count()])
