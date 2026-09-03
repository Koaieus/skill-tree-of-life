class_name AiCountRow
extends HBoxContainer
## AI count row: label + slider (0..12, expanding) + spinbox (0..12), with bidirectional linking.
## The slider and spinbox are kept in sync. The `value_changed` signal propagates from either control.

signal value_changed(v: float)

@onready var _slider: HSlider = %Slider
@onready var _spinbox: SpinBox = %SpinBox

var _updating := false

var value: float:
	get:
		return get_value()
	set(v):
		set_value(v)


func _ready() -> void:
	_slider.value_changed.connect(_on_slider_changed)
	_spinbox.value_changed.connect(_on_spinbox_changed)


## The bounds the screen offers, so [constant LobbyScreen._MAX_AI_OPPONENTS] is
## the one place the ceiling lives rather than a number authored twice in the
## scene's two controls.
func set_range(low: float, high: float) -> void:
	_slider.min_value = low
	_slider.max_value = high
	_spinbox.min_value = low
	_spinbox.max_value = high


func set_value(v: float) -> void:
	_slider.value = v
	_spinbox.value = v


func get_value() -> float:
	return _slider.value


func _on_slider_changed(v: float) -> void:
	if _updating:
		return
	_updating = true
	_spinbox.value = v
	_updating = false
	value_changed.emit(v)


func _on_spinbox_changed(v: float) -> void:
	if _updating:
		return
	_updating = true
	_slider.value = v
	_updating = false
	value_changed.emit(v)
