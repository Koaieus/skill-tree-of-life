@tool
extends PanelContainer

## Gate rope tuning bench: five node pairs of rising span (a longer rope rings
## lower), each drawn with a stand-in edge whose alpha follows the rope's
## reveal. Drives [method GateRope.play] directly — a Gate's own listener is
## dark in the editor. Tune the knobs on `graph/gate_rope.tscn`, then reload.

@export var rope_scene: PackedScene = preload("res://graph/gate_rope.tscn")
@export var color_a := Color(0.35, 0.8, 1.0)
@export var color_b := Color(1.0, 0.45, 0.8)
@export_range(4.0, 40.0) var node_radius := 16.0
@export var edge_tier := Emissive.Tier.LABEL

const PAIRS := 5
const ORIGIN := Vector2(120.0, 90.0)
const ROW := 120.0
const SPANS: Array[float] = [180.0, 260.0, 340.0, 440.0, 560.0]

var _open: Array[bool] = []
var _reveal: Array[float] = []
var _ropes: Array = []

@onready var _stage: Node2D = %Stage


func _ready() -> void:
	_open.resize(PAIRS)
	_reveal.resize(PAIRS)
	_ropes.resize(PAIRS)
	_open.fill(false)
	_reveal.fill(0.0)
	_stage.draw.connect(_draw_stage)
	%Open.pressed.connect(func() -> void: _set_open(0, true, GateRope.Mode.THROW))
	%Handshake.pressed.connect(func() -> void: _set_open(0, true, GateRope.Mode.HANDSHAKE))
	%Close.pressed.connect(func() -> void: _set_open(0, false, GateRope.Mode.SNAP))
	%ToggleAll.pressed.connect(_toggle_all)
	_stage.queue_redraw()


func _toggle_all() -> void:
	for i in PAIRS:
		_set_open(i, not _open[i], GateRope.Mode.SNAP if _open[i] else GateRope.Mode.THROW)


func _set_open(i: int, open: bool, mode: GateRope.Mode) -> void:
	if is_instance_valid(_ropes[i]):
		_ropes[i].queue_free()
	_open[i] = open
	_reveal[i] = 0.0
	var a := _node_a(i)
	var b := _node_b(i)
	var dir := (b - a).normalized()
	var rope := rope_scene.instantiate() as GateRope
	_stage.add_child(rope)
	_ropes[i] = rope
	rope.reveal_changed.connect(func(v: float) -> void:
		_reveal[i] = v
		_stage.queue_redraw())
	rope.finished.connect(func() -> void:
		_reveal[i] = 1.0 if _open[i] else 0.0
		_stage.queue_redraw())
	rope.play(mode, a + dir * node_radius, b - dir * node_radius, color_a, color_b, SPANS[0])
	_stage.queue_redraw()


func _node_a(i: int) -> Vector2:
	return ORIGIN + Vector2(0.0, ROW * i)


func _node_b(i: int) -> Vector2:
	return _node_a(i) + Vector2(SPANS[i], 0.0)


func _draw_stage() -> void:
	var stops := Emissive.stops(edge_tier)
	for i in PAIRS:
		var a := _node_a(i)
		var b := _node_b(i)
		if _open[i] and _reveal[i] > 0.0:
			var ca := Emissive.at(color_a, stops)
			var cb := Emissive.at(color_b, stops)
			ca.a = _reveal[i]
			cb.a = _reveal[i]
			_stage.draw_polyline_colors(PackedVector2Array([a, b]), PackedColorArray([ca, cb]), 3.0)
		_stage.draw_circle(a, node_radius, color_a)
		_stage.draw_circle(b, node_radius, color_b)


## The live-tab loader hook. The rope stage is self-contained — it builds its
## own node pairs — so a loaded object has nothing to feed it.
func load_object(_obj: Object) -> void:
	pass
