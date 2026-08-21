@tool
extends Node2D

## The disc + rim of one [BladeNode]. Holds no colour policy of its own — every
## hue, tier and width comes from the [BladeStyle] it is configured with, so the
## blade's look is tunable from one resource (#256).

var _radius: float = 32.0
var _is_pivot: bool = false
var _style: BladeStyle = null
var _tint: Color = Color.TRANSPARENT
var _disabled: bool = false


func configure(
		r: float,
		pivot: bool,
		style: BladeStyle,
		tint: Color = Color.TRANSPARENT,
		disabled: bool = false) -> void:
	_radius = r
	_is_pivot = pivot
	_style = style
	_tint = tint
	_disabled = disabled
	queue_redraw()


func _draw() -> void:
	if _style == null:
		return
	draw_circle(Vector2.ZERO, _radius, _style.fill_color(_is_pivot, _tint, _disabled), true)
	draw_circle(
			Vector2.ZERO, _radius,
			_style.rim_color(_is_pivot, _tint, _disabled),
			false, _style.rim_width, true)
