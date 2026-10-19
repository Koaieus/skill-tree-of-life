@tool
extends Node2D

## The rim band + shrug sheen of one [BladeNode]; the body under it is the
## sibling [BladeDome]. Holds no colour policy of its own — every
## hue, tier and width comes from the [BladeStyle] it is configured with, so the
## blade's look is tunable from one resource (#256).

var _radius: float = 32.0
var _inner_radius: float = 24.0
var _is_pivot: bool = false
var _style: BladeStyle = null
var _tint: Color = Color.TRANSPARENT
## #787: the old bool `disabled` de-lit interim is gone. Any progress > 0 means
## this vertex has popped — the disc stops drawing outright (replaced by
## ShatterField shards, `attack/melee/skill_blade.gd`), so nothing below reads
## this beyond the single early-return gate.
var _death_progress: float = 0.0
## [member BladeNode.shrug_progress]: while in (0, 1) a protective sheen band
## expands outward over the rim and fades.
var _shrug_progress: float = 0.0


func configure(
		r: float,
		inner_r: float,
		pivot: bool,
		style: BladeStyle,
		tint: Color = Color.TRANSPARENT,
		death_progress: float = 0.0,
		shrug_progress: float = 0.0) -> void:
	_radius = r
	_inner_radius = inner_r
	_is_pivot = pivot
	_style = style
	_tint = tint
	_death_progress = death_progress
	_shrug_progress = shrug_progress
	queue_redraw()


func _draw() -> void:
	if _style == null or _death_progress > 0.0:
		return
	# Rim band runs inner_radius → radius; stroke it as a ring centred in the
	# band so its outer edge lands exactly on radius (matching SkillNode).
	if _inner_radius >= _radius:
		return
	var band := _radius - _inner_radius
	var mid := (_inner_radius + _radius) / 2.0
	draw_circle(
			Vector2.ZERO, mid,
			_style.rim_color(_is_pivot, _tint, false),
			false, band, true)
	_draw_shrug_sheen(band, mid)


## The shrug sheen: a band as wide as the rim, starting on it and swelling
## outward by one more band width while it fades out.
func _draw_shrug_sheen(band: float, mid: float) -> void:
	if _shrug_progress <= 0.0 or _shrug_progress >= 1.0:
		return
	var sheen := _style.shrug_color()
	sheen.a *= 1.0 - _shrug_progress
	draw_circle(Vector2.ZERO, mid + band * _shrug_progress, sheen, false, band, true)
