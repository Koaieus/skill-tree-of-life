@tool
extends PanelContainer

## Live tab panel for Fault Line's crack ([FaultLineCrack]): a small authored
## board (`%Stage`'s discs and edges) the crack spreads over hop by hop on a
## fixed beat, each hop landing [code]share[/code] of its predecessor's Sunder
## so the crack visibly thins outward, and the weak-point crit (the last disc)
## shattering. Sliders tune the crack amount and the visual's own knobs live.

const _CRACK_SCENE := preload("res://ui/vfx/fault_line/fault_line_crack.tscn")
const _SUNDER_IDENTITY := preload("res://identity/defs/sunder.tres")

## The spread, wave by wave: each pair is (origin disc, target disc) under
## `%Stage`. The last target of the last wave is the weak point.
const _WAVES: Array = [
	[[&"N0", &"N1"], [&"N0", &"N2"]],
	[[&"N1", &"N3"], [&"N1", &"N4"], [&"N2", &"N5"]],
	[[&"N4", &"N6"], [&"N5", &"N7"]],
]
const _WEAK_POINT := &"N6"

@onready var _seed: HSlider = %Seed
@onready var _share: HSlider = %Share
@onready var _full: HSlider = %Full
@onready var _beat: HSlider = %Beat
@onready var _zoom: HSlider = %Zoom
@onready var _crit: CheckBox = %Crit
@onready var _replay: Button = %Replay
@onready var _loop: CheckBox = %Loop
@onready var _readout: Label = %Readout
@onready var _stage: Node2D = %Stage
@onready var _world: SubViewport = %World

var _live: Array[FaultLineCrack] = []
var _run: Tween = null


func noop(_obj: Object) -> void:
	pass


func _ready() -> void:
	for slider in [_seed, _share, _full, _beat, _zoom]:
		slider.value_changed.connect(_on_knob.unbind(1))
	_replay.pressed.connect(_play)
	_crit.toggled.connect(_play.unbind(1))
	_world.size_changed.connect(_centre)
	_centre()
	_on_knob()
	_play()


func _centre() -> void:
	_stage.position = Vector2(_world.size) * 0.5


func _on_knob() -> void:
	_stage.scale = Vector2.ONE * _zoom.value
	var stacks := PackedStringArray()
	for hop in _WAVES.size() + 1:
		stacks.append("%.1f" % _stacks_at(hop))
	_readout.text = "Sunder per hop: %s\nfull at %d · beat %.2fs · zoom %.2f" % [
		" → ".join(stacks), _full.value, _beat.value, _zoom.value]
	for crack in _live:
		if is_instance_valid(crack):
			crack.full_crack_stacks = _full.value


## Hop 0 lands the seed; each later hop lands `share` of its predecessor, never
## below the def's 1-stack floor (the crack's `min_value`).
func _stacks_at(hop: int) -> float:
	return maxf(_seed.value * pow(_share.value, hop), 1.0) if hop > 0 else _seed.value


func _play() -> void:
	if _run != null and _run.is_valid():
		_run.kill()
	for crack in _live:
		if is_instance_valid(crack):
			crack.queue_free()
	_live.clear()
	var beat: float = _beat.value
	_run = create_tween()
	for w in _WAVES.size():
		_run.tween_callback(_fire_wave.bind(w))
		_run.tween_interval(beat)
	var crack_probe: FaultLineCrack = _CRACK_SCENE.instantiate()
	_run.tween_interval(crack_probe.linger_seconds + 0.6)
	crack_probe.free()
	_run.tween_callback(_on_finished)


func _fire_wave(w: int) -> void:
	var flight: float = _beat.value * 0.9
	for pair: Array in _WAVES[w]:
		var from: Node2D = _stage.get_node(NodePath(String(pair[0])))
		var to: Node2D = _stage.get_node(NodePath(String(pair[1])))
		var crack: FaultLineCrack = _CRACK_SCENE.instantiate()
		crack.tint = _SUNDER_IDENTITY.tint
		crack.full_crack_stacks = _full.value
		_stage.add_child(crack)
		crack.edge_origin = from.position
		crack.edge_target = to.position
		var crit := 1 if _crit.button_pressed and pair[1] == _WEAK_POINT else 0
		crack.set_crack(_stacks_at(w + 1), crit)
		crack.finished.connect(crack.queue_free)
		_live.append(crack)
		crack._on_launch()
		var tween := create_tween()
		tween.tween_method(crack._on_progress, 0.0, 1.0, flight)
		tween.tween_callback(crack._on_arrival)


func _on_finished() -> void:
	if _loop.button_pressed:
		_play.call_deferred()
