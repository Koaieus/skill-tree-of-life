@tool
extends PanelContainer

## Toast sandbox panel — LIVE_EDIT tab for the Sandbox Host.
## Grid of N cells, each with its own [FloaterToaster] demonstrating one
## style from [FloaterStyles.gallery()], plus a "Random" cell.
## Controls: global Toast All / All ×3, per-cell buttons, auto-play with
## adjustable interval slider (0.5–5.0 s).

const FloaterStyles := preload("res://ui/floating_number_layer/floater_styles.gd")
const _TOASTER_SCENE: PackedScene = preload("res://ui/floating_number_layer/floater_toaster.tscn")
const _CELLS_W: int = 3
const _CELLS_H: int = 3
const _CELL_COUNT: int = _CELLS_W * _CELLS_H

# Cell colours — subtle background tints so each cell reads as distinct
# without needing heavy borders. Picked to complement the toast colours.
const _CELL_TINTS: Array[Color] = [
	Color(0.14, 0.14, 0.16, 1.0),
	Color(0.14, 0.15, 0.14, 1.0),
	Color(0.15, 0.14, 0.14, 1.0),
	Color(0.14, 0.14, 0.17, 1.0),
	Color(0.15, 0.15, 0.14, 1.0),
	Color(0.14, 0.16, 0.16, 1.0),
	Color(0.16, 0.14, 0.15, 1.0),
	Color(0.15, 0.14, 0.16, 1.0),
	Color(0.16, 0.16, 0.14, 1.0),
]

@onready var _toast_all_btn: Button = %ToastAllBtn
@onready var _toast_all_x3_btn: Button = %ToastAllX3Btn
@onready var _play_btn: Button = %PlayBtn
@onready var _interval_label: Label = %IntervalLabel
@onready var _interval_slider: HSlider = %IntervalSlider
@onready var _cell_grid: GridContainer = %CellGrid
@onready var _timer: Timer = %AutoTimer
@onready var _controls_bar: HBoxContainer = %ControlsBar
@onready var _per_cell_placeholder: HBoxContainer = %PerCellRow

var _gallery: Array
var _cell_toasters: Array[FloaterToaster] = []
var _playing: bool = false


## No-op: the toast sandbox is self-contained and doesn't receive
## inspector resources for routing (unlike spell/VFX/statboard tabs).
func load_object(_obj: Object) -> void:
	pass


func _ready() -> void:
	_gallery = FloaterStyles.gallery()

	_toast_all_btn.pressed.connect(_toast_all.bind(1))
	_toast_all_x3_btn.pressed.connect(_toast_all.bind(3))
	_play_btn.pressed.connect(_toggle_play)
	_interval_slider.value_changed.connect(_on_interval_changed)
	_timer.timeout.connect(_toast_all.bind(1))

	_build_cells()
	_build_per_cell_buttons()


func _build_cells() -> void:
	for i in _CELL_COUNT:
		var entry: Dictionary = _gallery[i] if i < _gallery.size() else {}
		var cell_name: String = entry.get("name", "Random") if not entry.is_empty() else "Random"

		var svc := SubViewportContainer.new()
		svc.name = "Cell_%d" % i
		svc.stretch = true
		svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_cell_grid.add_child(svc)

		var sv := SubViewport.new()
		sv.name = "Viewport"
		sv.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		sv.transparent_bg = true
		svc.add_child(sv)

		var tint: Color = _CELL_TINTS[i] if i < _CELL_TINTS.size() else _CELL_TINTS[0]
		var bg := ColorRect.new()
		bg.color = tint
		bg.anchors_preset = Control.PRESET_FULL_RECT
		sv.add_child(bg)
		sv.size_changed.connect(_on_cell_resized.bind(sv, bg))

		var label := Label.new()
		label.text = cell_name
		label.add_theme_font_size_override("font_size", 11)
		label.modulate = Color(0.55, 0.55, 0.55, 1.0)
		label.position = Vector2(4, 3)
		sv.add_child(label)

		var toaster := _TOASTER_SCENE.instantiate()
		toaster.max_queue_size = 16
		toaster.position = Vector2.ZERO
		sv.add_child(toaster)
		_cell_toasters.append(toaster)


func _on_cell_resized(sv: SubViewport, bg: ColorRect) -> void:
	bg.size = Vector2(sv.size)


func _build_per_cell_buttons() -> void:
	for i in _CELL_COUNT:
		var entry: Dictionary = _gallery[i] if i < _gallery.size() else {}
		var label: String = entry.get("name", "Rdm") if not entry.is_empty() else "Rdm"
		var abbr: String = label.substr(0, 3)

		var btn := Button.new()
		btn.text = abbr
		btn.flat = true
		btn.tooltip_text = "Toast in %s cell" % label
		btn.custom_minimum_size = Vector2(28, 22)
		btn.pressed.connect(_toast_cell.bind(i, 1))
		_per_cell_placeholder.add_child(btn)


func _toast_cell(index: int, count: int) -> void:
	if index < 0 or index >= _cell_toasters.size():
		return
	var toaster := _cell_toasters[index]
	if not is_instance_valid(toaster) or not toaster.is_inside_tree():
		toaster = _remake_toaster(index)

	var entry: Dictionary
	if index < _gallery.size():
		entry = _gallery[index]
	else:
		entry = _gallery[randi() % _gallery.size()]

	for _i in count:
		var req := FloaterRequest.new()
		req.text = entry["text"]
		req.style = entry["style"]
		toaster.add_toast(req)


func _remake_toaster(index: int) -> FloaterToaster:
	var sv: SubViewport = _cell_grid.get_child(index).get_node("Viewport")
	var toaster := _TOASTER_SCENE.instantiate()
	toaster.max_queue_size = 16
	toaster.position = Vector2.ZERO
	sv.add_child(toaster)
	_cell_toasters[index] = toaster
	return toaster


func _toast_all(count: int) -> void:
	if _cell_toasters.is_empty():
		return
	for i in _CELL_COUNT:
		_toast_cell(i, count)


func _toggle_play() -> void:
	_playing = not _playing
	if _playing:
		_play_btn.text = "⏸"
		_interval_slider.editable = false
		_timer.start(_interval_slider.value)
	else:
		_play_btn.text = "▶"
		_interval_slider.editable = true
		_timer.stop()


func _on_interval_changed(value: float) -> void:
	_interval_label.text = "%.1fs" % value
	if _playing:
		_timer.stop()
		_timer.start(value)
