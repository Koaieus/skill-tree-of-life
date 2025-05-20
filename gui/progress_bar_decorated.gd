extends NinePatchRect
class_name DecoratedProgressBar

@onready var _bar: ProgressBar = %ProgressBar


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_update_tooltip_text()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_progress_bar_value_changed(value: float) -> void:
	_update_tooltip_text()

func _on_progress_bar_changed() -> void:
	_update_tooltip_text()

func _update_tooltip_text() -> void:
	tooltip_text = "Next level: %d / %d" % [_bar.value, _bar.max_value]
