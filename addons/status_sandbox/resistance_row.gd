@tool
extends HBoxContainer

## One resistance slider: a label, a 0–1 slider and its readout. The panel
## instantiates one per distinct [member StatusDef.resistance_stat_id].

signal changed(stat_id: StringName, value: float)

var stat_id: StringName = &""

@onready var _name: Label = %Name
@onready var _slider: HSlider = %Slider
@onready var _value: Label = %Value


func setup(p_stat_id: StringName) -> void:
	stat_id = p_stat_id
	_name.text = String(p_stat_id).trim_suffix("_resistance")
	_slider.value_changed.connect(_on_value_changed)
	_value.text = "%.2f" % _slider.value


func get_value() -> float:
	return _slider.value


func _on_value_changed(v: float) -> void:
	_value.text = "%.2f" % v
	changed.emit(stat_id, v)
