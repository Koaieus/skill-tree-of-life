@tool
extends Node2D

## The disc + rim of one [BladeNode]. Holds no colour policy of its own — every
## hue, tier and width comes from the [BladeStyle] it is configured with, so the
## blade's look is tunable from one resource (#256).

var _radius: float = 32.0
var _inner_radius: float = 24.0
var _is_pivot: bool = false
var _style: BladeStyle = null
var _tint: Color = Color.TRANSPARENT
var _disabled: bool = false


func configure(
		r: float,
		inner_r: float,
		pivot: bool,
		style: BladeStyle,
		tint: Color = Color.TRANSPARENT,
		disabled: bool = false) -> void:
	_radius = r
	_inner_radius = inner_r
	_is_pivot = pivot
	_style = style
	_tint = tint
	_disabled = disabled
	queue_redraw()


func _draw() -> void:
	if _style == null:
		return
	draw_circle(Vector2.ZERO, _inner_radius, _style.fill_color(_is_pivot, _tint, _disabled), true)
	# Rim band runs inner_radius → radius; stroke it as a ring centred in the
	# band so its outer edge lands exactly on radius (matching SkillNode).
	if _inner_radius >= _radius:
		return
	var band := _radius - _inner_radius
	var mid := (_inner_radius + _radius) / 2.0
	draw_circle(
			Vector2.ZERO, mid,
			_style.rim_color(_is_pivot, _tint, _disabled),
			false, band, true)
