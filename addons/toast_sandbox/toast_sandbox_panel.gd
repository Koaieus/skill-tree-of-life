@tool
extends PanelContainer

## Toast sandbox panel — LIVE_EDIT tab for the Sandbox Host.
## Grid of N cells, each with its own [FloaterToaster] demonstrating one
## style from [FloaterStyles.gallery()], plus a "Random" cell.
## Controls: global Toast All / All ×3, per-cell buttons, auto-play with
## adjustable interval slider (0.5–5.0 s).

const FloaterStyles := preload("res://ui/floating_number_layer/floater_styles.gd")
const _TOAST_CELL_SCENE: PackedScene = preload("res://addons/toast_sandbox/toast_cell.tscn")
## Grid width. The HEIGHT is not a constant — the cell count follows
## [method FloaterStyles.gallery] (plus one "Random" cell), so adding a style
## shows up here instead of falling off the end of a hardcoded 3x3.
##
## 4 rather than 3 since the crit toast landed: cells are `size_flags_vertical =
## 3` inside an expanding grid, so more ROWS means shorter cells — and a crit
## toast (three of them, under "All x3") needs the height to be seen at all.
const _CELLS_W: int = 4

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
var _cell_count: int = 0
var _cells: Array[ToastCell] = []
var _playing: bool = false


## No-op: the toast sandbox is self-contained and doesn't receive
## inspector resources for routing (unlike spell/VFX/statboard tabs).
func load_object(_obj: Object) -> void:
	pass


func _ready() -> void:
	_gallery = FloaterStyles.gallery()
	# One cell per style, plus a trailing "Random" cell.
	_cell_count = _gallery.size() + 1
	_cell_grid.columns = _CELLS_W

	_toast_all_btn.pressed.connect(_toast_all.bind(1))
	_toast_all_x3_btn.pressed.connect(_toast_all.bind(3))
	_play_btn.pressed.connect(_toggle_play)
	_interval_slider.value_changed.connect(_on_interval_changed)
	_timer.timeout.connect(_toast_all.bind(1))

	_build_cells()
	_build_per_cell_buttons()


func _build_cells() -> void:
	for i in _cell_count:
		var entry: Dictionary = _gallery[i] if i < _gallery.size() else {}
		var cell_name: String = entry.get("name", "Random") if not entry.is_empty() else "Random"

		var cell: ToastCell = _TOAST_CELL_SCENE.instantiate()
		cell.name = "Cell_%d" % i
		cell.tint = _CELL_TINTS[i % _CELL_TINTS.size()]
		cell.label_text = cell_name
		_cell_grid.add_child(cell)
		_cells.append(cell)


func _build_per_cell_buttons() -> void:
	for i in _cell_count:
		var entry: Dictionary = _gallery[i] if i < _gallery.size() else {}
		var label: String = entry.get("name", "Rdm") if not entry.is_empty() else "Rdm"
		# First WORD-initials where the name has several ("Gold crit" -> "Gol"
		# and "Heat crit" -> "Hea" would both be fine, but "Crit gold" /
		# "Crit heat" would collide — so gallery names lead with the distinguishing
		# word, and this stays a plain prefix).
		var abbr: String = label.substr(0, 3)

		var btn := Button.new()
		btn.text = abbr
		btn.flat = true
		btn.tooltip_text = "Toast in %s cell" % label
		btn.custom_minimum_size = Vector2(28, 22)
		btn.pressed.connect(_toast_cell.bind(i, 1))
		_per_cell_placeholder.add_child(btn)


func _toast_cell(index: int, count: int) -> void:
	if index < 0 or index >= _cells.size():
		return
	var toaster := _cells[index].get_or_remake_toaster()

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


func _toast_all(count: int) -> void:
	if _cells.is_empty():
		return
	for i in _cell_count:
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
