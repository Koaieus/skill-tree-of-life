@tool
class_name MidasMarkVisual
extends AddonVisual

## The Midas Mark's drawing: a gilded rim with a glint sweeping round it, and
## [member coin_count] coins orbiting just outside, each flipping (its width
## squashes with a cosine) as it goes — one [method _draw] pass for all of
## them, never a node per coin (a level draws a few hundred carriers). Colour
## is the parent addon's identity tint; the glint glows on a named
## [enum Emissive.Tier].
##
## Animation is a pure function of time and a per-carrier seed, redrawn at
## [member redraw_hz] rather than every frame, and only while visible.

const _FALLBACK_TINT := Color(1.0, 0.8, 0.25)

## Coins orbiting one carrier — the hard per-node cap.
@export_range(0, 12, 1) var coin_count: int = 5:
	set(value):
		coin_count = value
		queue_redraw()
## A coin's radius, as a fraction of the carrier's radius.
@export_range(0.02, 0.3, 0.01) var coin_size: float = 0.11:
	set(value):
		coin_size = value
		queue_redraw()
## Coin orbit radius, × the carrier's radius.
@export_range(1.0, 2.0, 0.05) var orbit: float = 1.25:
	set(value):
		orbit = value
		queue_redraw()
## Orbit turns per second.
@export_range(0.0, 1.0, 0.01) var orbit_speed: float = 0.08:
	set(value):
		orbit_speed = value
		queue_redraw()
## Coin flips per second.
@export_range(0.0, 3.0, 0.05) var flip_speed: float = 0.6:
	set(value):
		flip_speed = value
		queue_redraw()
## Rim width, × the carrier's radius.
@export_range(0.01, 0.3, 0.01) var rim_width: float = 0.08:
	set(value):
		rim_width = value
		queue_redraw()
## Glint sweeps per second round the rim.
@export_range(0.0, 2.0, 0.05) var glint_speed: float = 0.4:
	set(value):
		glint_speed = value
		queue_redraw()
## The glint's arc length, in radians.
@export_range(0.1, 3.0, 0.05) var glint_arc: float = 0.7:
	set(value):
		glint_arc = value
		queue_redraw()
## Glow tier of the glint (`.claude/rules/hdr-color.md`); rim and coins stay
## a plain colour.
@export var glint_tier: Emissive.Tier = Emissive.Tier.LABEL:
	set(value):
		glint_tier = value
		queue_redraw()
## Redraw rate cap, in Hz.
@export_range(5.0, 60.0, 1.0) var redraw_hz: float = 20.0

var _time := 0.0
var _since_redraw := 0.0


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	_since_redraw += delta
	if _since_redraw >= 1.0 / redraw_hz:
		_since_redraw = 0.0
		queue_redraw()


## Derived, never authored: the parent addon's identity tint.
func _tint() -> Color:
	var addon := get_parent() as SkillNodeAddon
	if addon != null and addon.tint.a > 0.0:
		return addon.tint
	return _FALLBACK_TINT


## Stable per-carrier offset so neighbouring marks never glint in step.
func _seed() -> float:
	return fposmod(sin((global_position.x * 0.137 + global_position.y * 0.311) * 12.9898) * 43758.5453, 1.0)


func _draw() -> void:
	if radius <= 0.0:
		return
	var tint := _tint()
	var seed := _seed()
	var w := maxf(1.0, radius * rim_width)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(tint, 0.85), w)
	var glint := Emissive.at(tint, Emissive.stops(glint_tier))
	var start := TAU * fposmod(_time * glint_speed + seed, 1.0)
	draw_arc(Vector2.ZERO, radius, start, start + glint_arc, 12, glint, w * 1.4)
	if coin_count <= 0:
		return
	var size := radius * coin_size
	var dark := tint.darkened(0.35)
	for i in coin_count:
		var theta := TAU * (float(i) / float(coin_count) + _time * orbit_speed + seed)
		var center := Vector2.from_angle(theta) * radius * orbit
		var flip := absf(cos(TAU * (_time * flip_speed + float(i) * 0.37 + seed)))
		var sx := maxf(0.15, flip)
		draw_set_transform(center, 0.0, Vector2(sx, 1.0))
		draw_circle(Vector2.ZERO, size, tint)
		draw_arc(Vector2.ZERO, size, 0.0, TAU, 12, dark, maxf(1.0, size * 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
