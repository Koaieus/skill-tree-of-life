@tool
class_name CombatValueRow
extends HBoxContainer
## One "Label: Value" line in a Combat Readout card, with a [DeltaChip] that
## pops whenever [method set_value] sees the number change, plus an optional
## breakpoint sliver caption underneath (e.g. "+1 / 20 STR - next @60").

@onready var _label: Label = %Label
@onready var _value: Label = %Value
@onready var _sliver: Label = %Sliver
@onready var _chip: DeltaChip = %DeltaChip

@export var row_label: String = "":
	set(v):
		row_label = v
		if _label != null:
			_label.text = v

var _last_value: float = NAN

func _ready() -> void:
	if _label != null:
		_label.text = row_label
	if _sliver != null:
		_sliver.visible = false


func set_value(v: float, suffix: String = "") -> void:
	if _value != null:
		_value.text = "%d%s" % [int(v), suffix]
	if not is_nan(_last_value) and v != _last_value and _chip != null:
		_chip.pop(v - _last_value)
	_last_value = v


func set_sliver(text: String) -> void:
	if _sliver == null:
		return
	_sliver.visible = not text.is_empty()
	_sliver.text = text
