@tool
class_name SaplingVisual
extends AddonVisual

## The sapling's drawing: a dull ring just outside the carrier's rim that sags
## under its own weight — its lower half hangs lower and thicker — and gives a
## slow, heavy thud: a short swell that settles back, shedding one faint ring
## that drops and fades. One [method _draw] pass, no child nodes. Colour is the
## parent addon's identity tint, dulled toward grey; nothing glows (the look is
## a blunt, spent weight, not a light).
##
## Animation is a pure function of time and a per-carrier seed, redrawn at
## [member redraw_hz] and only while visible.

const _FALLBACK_TINT := Color(0.62, 0.55, 0.42)
const _GREY := Color(0.45, 0.45, 0.45)
const _SEGMENTS := 48

## The ring's radius, × the carrier's radius.
@export_range(1.0, 1.6, 0.01) var ring_radius: float = 1.18:
	set(value):
		ring_radius = value
		queue_redraw()
## How far the ring's bottom hangs below a true circle, × the carrier's radius.
@export_range(0.0, 0.4, 0.01) var sag: float = 0.12:
	set(value):
		sag = value
		queue_redraw()
## Line width at the ring's top, in px; the bottom is [member sag_thickening] × it.
@export_range(0.5, 8.0, 0.1) var line_width: float = 2.0:
	set(value):
		line_width = value
		queue_redraw()
## How much thicker the hanging bottom is than the top.
@export_range(1.0, 4.0, 0.1) var sag_thickening: float = 2.2:
	set(value):
		sag_thickening = value
		queue_redraw()
## How far the tint is dulled toward grey (0 = pure identity tint).
@export_range(0.0, 1.0, 0.05) var dullness: float = 0.4:
	set(value):
		dullness = value
		queue_redraw()
## Thuds per second — slow by design.
@export_range(0.05, 2.0, 0.05) var thud_rate: float = 0.4:
	set(value):
		thud_rate = value
		queue_redraw()
## A thud's swell, as a fraction of the ring's radius.
@export_range(0.0, 0.3, 0.01) var thud_swell: float = 0.06:
	set(value):
		thud_swell = value
		queue_redraw()
## How quickly a thud settles (higher = a shorter, blunter knock).
@export_range(1.0, 20.0, 0.5) var thud_damping: float = 7.0:
	set(value):
		thud_damping = value
		queue_redraw()
## How far the shed ring drops and widens over one thud, × the carrier's radius.
@export_range(0.0, 1.0, 0.05) var shed_distance: float = 0.35:
	set(value):
		shed_distance = value
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


## Derived, never authored: the parent addon's identity tint, dulled.
func _tint() -> Color:
	var addon := get_parent() as SkillNodeAddon
	var tint := _FALLBACK_TINT
	if addon != null and addon.tint.a > 0.0:
		tint = addon.tint
	return tint.lerp(_GREY, dullness)


## Stable per-carrier offset so neighbouring saplings never thud in step.
func _seed() -> float:
	return fposmod(sin((global_position.x * 0.137 + global_position.y * 0.311) * 12.9898) * 43758.5453, 1.0)


## The sagging ring's points at base radius [param r], hanging by [param hang].
func _ring(r: float, hang: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in _SEGMENTS + 1:
		var theta := TAU * float(i) / float(_SEGMENTS)
		var down := 0.5 + 0.5 * sin(theta)  # +y is down: 1 at the bottom, 0 at the top
		pts.append(Vector2.from_angle(theta) * r + Vector2(0.0, hang * down * down))
	return pts


func _draw() -> void:
	if radius <= 0.0:
		return
	var tint := _tint()
	var phase := fposmod(_time * thud_rate + _seed(), 1.0)
	var knock := exp(-phase * thud_damping)
	var r := radius * ring_radius * (1.0 + thud_swell * knock)
	var hang := radius * sag * (1.0 + knock * 0.5)
	var pts := _ring(r, hang)
	var colors := PackedColorArray()
	for i in pts.size():
		colors.append(Color(tint, 0.85))
	# Two passes: a thin full ring, then a heavier lower half for the sag.
	draw_polyline_colors(pts, colors, line_width)
	var lower := pts.slice(0, (_SEGMENTS >> 1) + 1)
	draw_polyline(lower, Color(tint, 0.6), line_width * sag_thickening)
	# The shed ring: drops and widens as the thud settles, fading out.
	var shed := _ring(r + radius * shed_distance * phase * 0.5, hang + radius * shed_distance * phase)
	draw_polyline(shed, Color(tint, 0.35 * (1.0 - phase)), maxf(1.0, line_width * 0.6))
