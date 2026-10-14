@tool
extends PanelContainer

## Live tab panel for the board blast ring ([BlastVisual]): reach and power
## sliders, a rider picker (one layer per ticked aspect, as [BlastVFX] lays
## them), a zoom to judge it at three camera scales, and a replay. A fixed
## disc stands in for the blast's node so the reach reads against it.

const _VISUAL_SCENE := preload("res://ui/vfx/blast_visual.tscn")
const _LAYER_SCENE := preload("res://ui/vfx/rider_blast_layer.tscn")

@onready var _reach: HSlider = %Reach
@onready var _power: HSlider = %Power
@onready var _zoom: HSlider = %Zoom
@onready var _replay: Button = %Replay
@onready var _loop: CheckBox = %Loop
@onready var _readout: Label = %Readout
@onready var _riders: VBoxContainer = %Riders
@onready var _stage: Node2D = %Stage
@onready var _world: SubViewport = %World

var _visual: BlastVisual = null
var _roster: AspectRoster = AspectRoster.shared()
## Rider identity per picker box, in roster order.
var _picks: Dictionary[CheckBox, Identity] = {}


func noop(_obj: Object) -> void:
	pass


func _ready() -> void:
	for slider in [_reach, _power, _zoom]:
		slider.value_changed.connect(_on_knob.unbind(1))
	_replay.pressed.connect(_play)
	_build_picker()
	_world.size_changed.connect(_centre)
	_centre()
	_on_knob()
	_play()


## One box per roster aspect but explosive (a blast strips its own charges).
func _build_picker() -> void:
	for aspect in _roster.aspects:
		if aspect == null or aspect.identity == null or aspect.id() == &"explosive":
			continue
		var box := CheckBox.new()
		box.text = aspect.identity.noun if not aspect.identity.noun.is_empty() else String(aspect.id())
		box.add_theme_color_override(&"font_color", aspect.identity.tint)
		box.toggled.connect(_play.unbind(1))
		_riders.add_child(box)
		_picks[box] = aspect.identity


func _picked() -> Array[Identity]:
	var out: Array[Identity] = []
	for box: CheckBox in _picks:
		if box.button_pressed:
			out.append(_picks[box])
	return out


func _centre() -> void:
	_stage.position = Vector2(_world.size) * 0.5


func _on_knob() -> void:
	_stage.scale = Vector2.ONE * _zoom.value
	_readout.text = "reach %d px · power %d · zoom %.2f" % [_reach.value, _power.value, _zoom.value]
	if _visual != null:
		_visual.radius = _reach.value
		_visual.power = int(_power.value)


func _play() -> void:
	if _visual != null:
		_visual.queue_free()
	_visual = _VISUAL_SCENE.instantiate() as BlastVisual
	_stage.add_child(_visual)
	_visual.radius = _reach.value
	_visual.power = int(_power.value)
	_visual.riders = _picked()
	_visual.companions = BlastVFX.layers_for(_visual.riders, _roster, _LAYER_SCENE)
	_visual.finished.connect(_on_finished)
	_visual.play()


func _on_finished() -> void:
	if _loop.button_pressed:
		_play.call_deferred()
