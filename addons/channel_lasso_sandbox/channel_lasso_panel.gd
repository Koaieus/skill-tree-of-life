@tool
extends PanelContainer

## Channel lasso tuning bench: five core → node pairs at rising distance
## against one leash, so tension reads slack (top) to taut (bottom). The step
## fraction ramps on a loop and flashes at each wrap. Drives
## [method ChannelLasso.drive] — a bound lasso needs a live AllocationSystem.
## Tune the knobs on `ui/vfx/channel_lasso/channel_lasso.tscn`, then reload.

@export var lasso_scene: PackedScene = preload("res://ui/vfx/channel_lasso/channel_lasso.tscn")
@export var owner_color := Color(0.35, 0.8, 1.0)
@export_range(4.0, 40.0) var node_radius := 14.0
@export_range(50.0, 1000.0, 1.0, "suffix:px") var leash_px := 520.0
## Seconds one step takes to fill (the fraction 0 → 1 loop).
@export_range(0.2, 10.0, 0.1, "suffix:s") var step_seconds := 2.5

const PAIRS := 5
const ORIGIN := Vector2(90.0, 80.0)
const ROW := 120.0
const SPANS: Array[float] = [120.0, 220.0, 320.0, 420.0, 520.0]
const CORE_JUMP := Vector2(-60.0, 40.0)

var _lassos: Array[ChannelLasso] = []
var _core_offsets: Array[Vector2] = []
var _direction := 1
var _clock := 0.0

@onready var _stage: Node2D = %Stage


func _ready() -> void:
	_core_offsets.resize(PAIRS)
	_core_offsets.fill(Vector2.ZERO)
	for i in PAIRS:
		var lasso := lasso_scene.instantiate() as ChannelLasso
		_stage.add_child(lasso)
		_lassos.append(lasso)
	_stage.draw.connect(_draw_stage)
	%Step.pressed.connect(_step_all)
	%MoveCore.pressed.connect(_move_cores)
	%Reverse.pressed.connect(func() -> void: _direction = -_direction)
	_drive(0.0)


func _process(delta: float) -> void:
	var before := _fraction()
	_clock += delta
	if _fraction() < before:
		_step_all()
	_drive(_fraction())
	_stage.queue_redraw()


func _fraction() -> float:
	return fposmod(_clock, step_seconds) / step_seconds


func _drive(fraction: float) -> void:
	for i in _lassos.size():
		_lassos[i].drive(_core(i), _node(i), owner_color, fraction, _direction, leash_px)


func _step_all() -> void:
	for lasso in _lassos:
		lasso.on_stepped()


func _move_cores() -> void:
	for i in PAIRS:
		_core_offsets[i] = Vector2.ZERO if _core_offsets[i] != Vector2.ZERO else CORE_JUMP
	_drive(_fraction())
	for lasso in _lassos:
		lasso.on_core_moved()


func _core(i: int) -> Vector2:
	return ORIGIN + Vector2(0.0, ROW * i) + _core_offsets[i]


func _node(i: int) -> Vector2:
	return ORIGIN + Vector2(SPANS[i], ROW * i)


func _draw_stage() -> void:
	for i in PAIRS:
		_stage.draw_circle(_core(i), node_radius * 1.3, owner_color)
		_stage.draw_arc(_node(i), node_radius, 0.0, TAU, 32, owner_color, 2.0)


## The live-tab loader hook. The stage is self-contained, so a loaded object
## has nothing to feed it.
func load_object(_obj: Object) -> void:
	pass
