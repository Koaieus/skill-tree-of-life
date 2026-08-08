@tool
class_name CombatValueRow
extends HBoxContainer
## One "Label: Value" line in a Combat Readout card, with a [DeltaChip] that
## pops whenever [method set_value] sees the number change, plus an optional
## breakpoint sliver caption underneath (e.g. "+1 / 20 STR - next @60").
##
## #119 — also supports a persistent "this value is overridden" display mode
## ([method show_override]/[method clear_override]), used when hovering a
## SkillNode whose local stat differs from the entity baseline. Deliberately
## NOT the [DeltaChip] — that's a 2.7s transient pop for a stat CHANGING;
## this is a held state for as long as the node stays hovered, and needs to
## coexist with (not fight) normal baseline updates arriving mid-hover.

@onready var _label: Label = %Label
@onready var _value: Label = %Value
@onready var _sliver: Label = %Sliver
@onready var _chip: DeltaChip = %DeltaChip
@onready var _override_badge: Label = %OverrideBadge

@export var row_label: String = "":
	set(v):
		row_label = v
		if _label != null:
			_label.text = v

## ALERT tier (#390) — a node-local override is exactly the "genuine
## punctuation" the tier vocabulary reserves ALERT for: the value differs
## from baseline right now.
@export var override_color: Color = Emissive.at(Color(0.9, 0.75, 0.4), Emissive.ALERT)

var _last_value: float = NAN
var _last_suffix: String = ""
var _override_active: bool = false
var _override_value: float = 0.0

var _delta_baseline: float = NAN
var _delta_pending: bool = false

func _ready() -> void:
	if _label != null:
		_label.text = row_label
	if _sliver != null:
		_sliver.visible = false
	if _override_badge != null:
		_override_badge.visible = false


func set_value(v: float, suffix: String = "") -> void:
	if not _delta_pending:
		_delta_baseline = _last_value
		_delta_pending = true
		call_deferred("_flush_delta")
	_last_value = v
	_last_suffix = suffix
	_render()


func _flush_delta() -> void:
	_delta_pending = false
	if is_nan(_delta_baseline) or _override_active or _chip == null:
		return
	var delta := _last_value - _delta_baseline
	if delta != 0.0:
		_chip.pop(delta)


func set_sliver(text: String) -> void:
	if _sliver == null:
		return
	_sliver.visible = not text.is_empty()
	_sliver.text = text


## Persistently displays `overridden` instead of the last baseline
## [method set_value], with distinct styling + a small badge. Caller (the
## combat card) only invokes this for rows whose node-local value actually
## differs from baseline — equal-valued rows should call [method
## clear_override] instead so unchanged stats don't light up.
func show_override(overridden: float) -> void:
	_override_active = true
	_override_value = overridden
	_render()


## Reverts to the last baseline value/suffix set via [method set_value].
func clear_override() -> void:
	if not _override_active:
		return
	_override_active = false
	_render()


func _render() -> void:
	if _value == null:
		return
	if _override_active:
		_value.text = "%d%s" % [int(_override_value), _last_suffix]
		_value.add_theme_color_override(&"font_color", override_color)
	else:
		_value.text = "%d%s" % [int(_last_value), _last_suffix]
		_value.remove_theme_color_override(&"font_color")
	if _override_badge != null:
		_override_badge.visible = _override_active
