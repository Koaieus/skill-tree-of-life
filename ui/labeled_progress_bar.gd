@tool
class_name LabeledProgressBar
extends ProgressBar

## A ProgressBar with a centred Label child showing arbitrary text. Used by
## the stats panel for pool-stat rows and by SkillNodeTooltip for HP bars.
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
