@tool
class_name LabeledProgressBar
extends ProgressBar

## A ProgressBar with a centred Label child showing arbitrary text. Used by
## the stats panel for pool-stat rows and by HpReadout for HP bars.
##
## Layout (anchors + offsets) lives in the .tscn so the editor and runtime
## resolve identical rects — earlier script-driven layout left the label
## visually bottom-aligned at certain bar heights. Instantiate via
## `LabeledProgressBar.create()` and refresh via `set_values()`.

const SCENE: PackedScene = preload("res://ui/labeled_progress_bar.tscn")

@onready var label: Label = $Text

static func create() -> LabeledProgressBar:
	return SCENE.instantiate() as LabeledProgressBar


func set_values(text: String, current: float, maximum: float, tint: Color) -> void:
	# self_modulate tints the bar's own drawing without bleeding into the
	# label child (modulate would dim the text along with the fill).
	self_modulate = tint
	max_value = max(1.0, maximum)
	value = current
	if label != null:
		label.text = text


# --- Animated path (#72) ----------------------------------------------------
# Used by the stats panel: owns the prefix/cap so it can rebuild the
# "Name: cur/max" string each tween step while the bar fills. First call snaps
# (panel build); later ones tween. Returns the delta in `current` so the panel
# can pop a diff floater. set_values() above is the un-animated path (tooltips).

const TWEEN_TIME: float = 0.3

var _prefix: String = ""
var _cap: float = 1.0
var _shown_current: float = 0.0
var _initialized: bool = false
var _tween: Tween


func animate_to(prefix: String, current: float, maximum: float, tint: Color) -> float:
	self_modulate = tint
	_prefix = prefix
	_cap = max(1.0, maximum)
	max_value = _cap
	if not _initialized:
		_initialized = true
		_shown_current = current
		_render(current)
		return 0.0
	if is_equal_approx(current, _shown_current):
		_render(_shown_current)  # cap may have moved — keep the "/max" fresh
		return 0.0
	var from := _shown_current
	_shown_current = current
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_render, from, current, TWEEN_TIME)
	return current - from


func _render(c: float) -> void:
	value = c
	if label != null:
		label.text = "%s: %d/%d" % [_prefix, int(round(c)), int(_cap)]
