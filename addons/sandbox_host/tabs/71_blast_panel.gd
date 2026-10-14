@tool
extends PanelContainer

## Live tab panel for the board blast ring ([BlastVisual]): reach and power
## sliders, a zoom to judge it at three camera scales, and a replay. A fixed
## disc stands in for the blast's node so the reach reads against it.

const _VISUAL_SCENE := preload("res://ui/vfx/blast_visual.tscn")

@onready var _reach: HSlider = %Reach
@onready var _power: HSlider = %Power
@onready var _zoom: HSlider = %Zoom
@onready var _replay: Button = %Replay
@onready var _loop: CheckBox = %Loop
@onready var _readout: Label = %Readout
@onready var _stage: Node2D = %Stage
@onready var _world: SubViewport = %World

var _visual: BlastVisual = null


func noop(_obj: Object) -> void:
	pass


func _ready() -> void:
	for slider in [_reach, _power, _zoom]:
		slider.value_changed.connect(_on_knob.unbind(1))
	_replay.pressed.connect(_play)
	_world.size_changed.connect(_centre)
	_centre()
	_on_knob()
	_play()


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
	_visual.finished.connect(_on_finished)
	_visual.play()


func _on_finished() -> void:
	if _loop.button_pressed:
		_play.call_deferred()
