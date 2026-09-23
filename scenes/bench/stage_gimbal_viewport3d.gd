extends Node2D
## The [code]viewport3d[/code] stage-gimbal substrate (#1074, shape A): one
## [Gimbal3D] rig registered with the level's single [GimbalWorld], adapted
## onto the three-property contract every row of [code]IdleTurnProbe[/code]'s
## substrate table shares. This Node2D is the rig's 2D anchor: its global
## position is mirrored onto the 3D holder, so moving it moves the rings.

## Matches the cpu2d footprint: CoreHalos at halo_scale 1.8 spans
## radius * 1.8 * (1 + 4 * 0.22) = 3.38r for 5 rings; the 3D chain spans
## base * (1 + 4 * 0.34) = 2.36 base, so base = 1.43r puts both outer rings
## on the same px — the fill comparison is like for like.
const BASE_RADIUS_SCALE := 3.384 / 2.36

@export var style: Gimbal3D.Style = Gimbal3D.Style.HOLO_GLASS

@export_range(1, 5, 1) var ring_count: int = 5:
	set(value):
		ring_count = value
		if _rig != null:
			_rig.ring_count = value

@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		if _rig != null:
			_rig.tint = value

## The SkillNode radius the gimbal sits on, px; also the occluder disc radius.
@export var base_radius: float = 32.0:
	set(value):
		base_radius = value
		if _rig != null:
			_rig.base_radius = value * BASE_RADIUS_SCALE

var _rig: Gimbal3D
var _holder: Node3D


func _ready() -> void:
	var world := GimbalWorld.acquire(self)
	_rig = Gimbal3D.new()
	_rig.style = _style_from_cmdline()
	_rig.ring_count = ring_count
	_rig.tint = tint
	_rig.base_radius = base_radius * BASE_RADIUS_SCALE
	_holder = world.add_rig(_rig, global_position, base_radius)
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and _holder != null:
		_holder.position = GimbalWorld.to_world_3d(global_position)


func _exit_tree() -> void:
	if _holder != null:
		_holder.queue_free()
		_holder = null


## `--gimbal-style=<UNIFORM_GLOW|HOLO_GLASS|SOLID_GLYPH>` on the bench command
## line overrides the export (the probe's contract has no style property).
func _style_from_cmdline() -> Gimbal3D.Style:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--gimbal-style="):
			var key := arg.get_slice("=", 1).to_upper()
			if Gimbal3D.Style.has(key):
				return Gimbal3D.Style[key]
	return style
