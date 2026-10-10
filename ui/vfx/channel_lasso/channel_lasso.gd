@tool
class_name ChannelLasso
extends Node2D

## The live electric lasso from a channelling node's owner core to the node —
## presentation only. Tension-led: slack and wavy when the core is close,
## taut and crackly as it nears the leash; brightness climbs with the step's
## fraction, pulses run in the channel's direction. All motion is the
## shader's own `TIME`; the CPU pushes endpoint/tension/fraction uniforms,
## read live each frame (never stored), and integrates one damped spring on
## the core end so an instant core swap whips. A [ChannelLassoDirector]
## owns the lifetime. Knobs: issue #1549.

@export_group("Shape")
@export_range(2, 96, 1) var segments := 24:
	set(v):
		segments = v
		_rebuild_strip()
@export_range(0.5, 16.0, 0.1, "suffix:px") var width := 2.5:
	set(v):
		width = v
		_push_knobs()
## Lateral amplitude at tension 0, as a fraction of the span.
@export_range(0.0, 0.5, 0.005) var slack_amplitude := 0.12:
	set(v):
		slack_amplitude = v
		_push_knobs()
## Lateral amplitude at tension 1 (core at the leash).
@export_range(0.0, 0.5, 0.005) var taut_amplitude := 0.02:
	set(v):
		taut_amplitude = v
		_push_knobs()
@export_range(0.0, 10.0, 0.05, "suffix:Hz") var wave_hz := 1.2:
	set(v):
		wave_hz = v
		_push_knobs()
## High-frequency jitter's share of the displacement at tension 0.
@export_range(0.0, 1.0, 0.01) var crackle_slack := 0.1:
	set(v):
		crackle_slack = v
		_push_knobs()
## … and at tension 1.
@export_range(0.0, 1.0, 0.01) var crackle_taut := 0.8:
	set(v):
		crackle_taut = v
		_push_knobs()
@export_group("Pulses")
@export_range(0.0, 4.0, 0.01, "suffix:spans/s") var pulse_speed := 0.6:
	set(v):
		pulse_speed = v
		_push_knobs()
@export_range(0.05, 1.0, 0.01, "suffix:spans") var pulse_spacing := 0.25:
	set(v):
		pulse_spacing = v
		_push_knobs()
## How far a pulse head mixes toward [member step_flash]'s tier.
@export_range(0.0, 1.0, 0.01) var pulse_strength := 0.5:
	set(v):
		pulse_strength = v
		_push_knobs()
@export_group("Glow")
## Tier at fraction 0; the lasso climbs in EV stops to [member lasso_tier_full].
@export var lasso_tier := Emissive.Tier.LABEL
@export var lasso_tier_full := Emissive.Tier.VALUE
## Flash on the node when a step lands; also the pulse heads' tier.
@export var step_flash := Emissive.Tier.PEAK
@export_range(1.0, 60.0, 0.5, "suffix:px") var flash_radius := 12.0
@export_range(0.02, 1.0, 0.01, "suffix:s") var flash_duration := 0.3
@export_group("Core spring")
@export_range(1.0, 400.0, 0.5) var core_spring_stiffness := 40.0
@export_range(0.0, 60.0, 0.1) var core_spring_damping := 8.0
## Sideways kick on a core move, as px/s per px the core jumped.
@export_range(0.0, 20.0, 0.1) var core_whip_kick := 3.0

var _node: SkillNode
var _allocation_system: AllocationSystem
## Sandbox seam: endpoints handed in by [method drive] when nothing is bound.
var _driven := false
var _drive_core := Vector2.ZERO
var _drive_node := Vector2.ZERO
var _drive_color := Color.WHITE
var _drive_fraction := 0.0
var _drive_direction := 1
var _drive_leash := 1.0

var _core_draw := Vector2.ZERO
var _core_vel := Vector2.ZERO
var _spring_live := false
var _flash_age := INF
var _color := Color.WHITE
var _node_local := Vector2.ZERO

@onready var _strip: MeshInstance2D = %Strip


func _ready() -> void:
	_rebuild_strip()
	_push_knobs()
	set_process(_node != null or _driven)


## Follow [param node]'s channel; owner, core, fraction and leash are read
## live from [param node] and [param allocation_system] every frame.
func bind(node: SkillNode, allocation_system: AllocationSystem) -> void:
	_node = node
	_allocation_system = allocation_system
	_driven = false
	_spring_live = false
	set_process(true)


## Sandbox seam: drive the lasso by hand, no [SkillNode] needed. Ignored while
## bound. [param direction] is +1 stake, −1 extract.
func drive(core_global: Vector2, node_global: Vector2, color: Color,
		fraction: float, direction: int, leash_px: float) -> void:
	_drive_core = core_global
	_drive_node = node_global
	_drive_color = color
	_drive_fraction = fraction
	_drive_direction = direction
	_drive_leash = leash_px
	_driven = true
	set_process(true)


## A step landed: flash the node end.
func on_stepped() -> void:
	_flash_age = 0.0
	queue_redraw()


## The owner's core swapped instantly: the drawn end lags on its spring
## already; kick it sideways so it whips.
func on_core_moved() -> void:
	var target: Variant = _core_global()
	if target == null or not _spring_live:
		return
	var jump: Vector2 = (target as Vector2) - _core_draw
	_core_vel += jump.orthogonal() * core_whip_kick


func _process(delta: float) -> void:
	var core: Variant = _core_global()
	var node_global: Variant = _node_global()
	if core == null or node_global == null:
		_strip.visible = false
		return
	_strip.visible = true
	_step_spring(core, minf(delta, 1.0 / 30.0))
	_node_local = to_local(node_global)
	var core_local := to_local(_core_draw)
	var fraction := _fraction()
	var leash := _leash()
	var tension := clampf((core as Vector2).distance_to(node_global) / maxf(leash, 1.0), 0.0, 1.0)
	_color = _owner_color()
	var mat := _strip.material as ShaderMaterial
	mat.set_shader_parameter(&"from_pos", core_local)
	mat.set_shader_parameter(&"to_pos", _node_local)
	mat.set_shader_parameter(&"tension", tension)
	mat.set_shader_parameter(&"direction", float(_direction()))
	mat.set_shader_parameter(&"color", Emissive.at(_color,
		lerpf(Emissive.stops(lasso_tier), Emissive.stops(lasso_tier_full), fraction)))
	mat.set_shader_parameter(&"pulse_color", Emissive.at(_color, Emissive.stops(step_flash)))
	var reach := 1.35 * slack_amplitude * core_local.distance_to(_node_local) + width * 4.0
	var box := Rect2(core_local, Vector2.ZERO).expand(_node_local).grow(reach)
	RenderingServer.canvas_item_set_custom_rect(_strip.get_canvas_item(), true, box)
	if _flash_age < flash_duration:
		_flash_age += delta
		queue_redraw()


func _step_spring(target: Vector2, dt: float) -> void:
	if not _spring_live:
		_core_draw = target
		_core_vel = Vector2.ZERO
		_spring_live = true
		return
	var acc := (target - _core_draw) * core_spring_stiffness - _core_vel * core_spring_damping
	_core_vel += acc * dt
	_core_draw += _core_vel * dt


func _draw() -> void:
	if _flash_age >= flash_duration:
		return
	var k := 1.0 - _flash_age / flash_duration
	k *= k
	var c := Emissive.at(_color, Emissive.stops(step_flash))
	c.a *= k
	draw_circle(_node_local, flash_radius * (1.0 + 0.6 * (1.0 - k)), c)


func _bound() -> bool:
	return _node != null and is_instance_valid(_node)


func _core_global() -> Variant:
	if _bound():
		var owner_entity := _node.owned_by
		if owner_entity == null or not is_instance_valid(owner_entity) \
				or owner_entity.core_location == null:
			return null
		return owner_entity.core_location.global_position
	return _drive_core if _driven else null


func _node_global() -> Variant:
	if _bound():
		return _node.global_position
	return _drive_node if _driven else null


func _owner_color() -> Color:
	if _bound():
		return _node.owned_by.color
	return _drive_color


func _fraction() -> float:
	if _bound():
		return _allocation_system.channel_fraction(_node) if _allocation_system != null else 0.0
	return _drive_fraction


func _direction() -> int:
	return _node.channel_direction() if _bound() else _drive_direction


func _leash() -> float:
	if _bound():
		return _allocation_system.stake_leash_px() if _allocation_system != null else 1.0
	return _drive_leash


func _rebuild_strip() -> void:
	if not is_node_ready():
		return
	_strip.mesh = RopeStrip.build(1.0, segments, 1)
	_push_knobs()


func _push_knobs() -> void:
	if not is_node_ready():
		return
	var mat := _strip.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter(&"segments", float(segments))
	mat.set_shader_parameter(&"width", width)
	mat.set_shader_parameter(&"slack_amplitude", slack_amplitude)
	mat.set_shader_parameter(&"taut_amplitude", taut_amplitude)
	mat.set_shader_parameter(&"wave_hz", wave_hz)
	mat.set_shader_parameter(&"crackle_slack", crackle_slack)
	mat.set_shader_parameter(&"crackle_taut", crackle_taut)
	mat.set_shader_parameter(&"pulse_speed", pulse_speed)
	mat.set_shader_parameter(&"pulse_spacing", pulse_spacing)
	mat.set_shader_parameter(&"pulse_strength", pulse_strength)
