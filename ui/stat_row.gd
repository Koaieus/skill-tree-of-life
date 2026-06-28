extends HBoxContainer

## Animated stat row (#72). Owns its own tween + last-shown value so the panel
## stays a thin dispatcher (see stats_panel.gd). apply() tweens the displayed
## number to the new value, int-aware per the stat's value_type, flashes the
## value to draw the eye, and RETURNS the delta so the panel can pop a diff
## floater. The first apply() (panel build) snaps; later ones animate.
##
## No class_name on purpose: instantiated from stat_row.tscn and driven via a
## duck-typed apply() in the panel, so adding this script needs no global-class-
## cache refresh.

const TWEEN_TIME: float = 0.3

@onready var _name_label: Label = $Name
@onready var _value_label: Label = $Value

var _shown: float = 0.0
var _initialized: bool = false
var _value_type: int = StatDef.ValueType.INT
var _tween: Tween


## Render `value`. Returns the delta vs the previously shown value — 0.0 on the
## first call or when unchanged, so the caller only spawns a diff on real moves.
func apply(stat_name: String, value: float, value_type: int, tint: Color, is_inline: bool) -> float:
	_value_type = value_type
	if _name_label != null:
		# Inline sub-rows prefix "+" (this adds to the stat above).
		_name_label.text = ("+ " + stat_name) if is_inline else stat_name
	if not _initialized:
		_initialized = true
		_shown = value
		_render(value)
		return 0.0
	if is_equal_approx(value, _shown):
		return 0.0
	var from := _shown
	_shown = value
	_animate(from, value, tint)
	return value - from


func _animate(from: float, to: float, tint: Color) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_render, from, to, TWEEN_TIME)
	if _value_label != null:
		# self_modulate (not modulate) so an INLINE row's dimmed modulate.a is
		# preserved while the value flashes back from tint → white.
		_value_label.self_modulate = tint.lerp(Color.WHITE, 0.15)
		var flash := create_tween()
		flash.tween_property(_value_label, "self_modulate", Color.WHITE, TWEEN_TIME * 1.5) \
				.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


func _render(v: float) -> void:
	if _value_label == null:
		return
	if _value_type == StatDef.ValueType.FLOAT:
		_value_label.text = "%.1f" % v
	else:
		_value_label.text = "%d" % roundi(v)
