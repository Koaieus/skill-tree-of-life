@tool
class_name DoombrandVisual
extends AddonVisual

## Doombrand's drawing: a pentagram inscribed in a ring on the carrier,
## slowly turning, its strokes pulsing on a named [enum Emissive.Tier]. One
## [method _draw] pass, no child nodes (a level draws a few hundred
## carriers). Colour is the parent addon's identity tint (curse).
##
## Animation is a pure function of time and a per-carrier seed, redrawn at
## [member redraw_hz] and only while visible. Sizes are fractions of the
## carrier's radius.

const _FALLBACK_TINT := Color(0.55, 0.2, 0.75)

## The pentagram's circumradius, × the carrier's radius.
@export_range(0.2, 1.2, 0.01) var star_size: float = 0.62:
	set(value):
		star_size = value
		queue_redraw()
## Turns per second; 0 = still.
@export_range(0.0, 1.0, 0.01) var spin_hz: float = 0.05:
	set(value):
		spin_hz = value
		queue_redraw()
## Glow pulses per second.
@export_range(0.0, 4.0, 0.05) var pulse_hz: float = 0.6:
	set(value):
		pulse_hz = value
		queue_redraw()
## How far a pulse dims the strokes between peaks, 0 = steady.
@export_range(0.0, 1.0, 0.05) var pulse_depth: float = 0.45:
	set(value):
		pulse_depth = value
		queue_redraw()
## Stroke width, × the carrier's radius.
@export_range(0.01, 0.2, 0.005) var stroke: float = 0.06:
	set(value):
		stroke = value
		queue_redraw()
## Glow tier of the star's strokes (`.claude/rules/hdr-color.md`); the ring
## stays plain colour.
@export var glow_tier: Emissive.Tier = Emissive.Tier.VALUE:
	set(value):
		glow_tier = value
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


## Stable per-carrier offset so neighbouring brands never turn in step.
func _seed() -> float:
	return fposmod(sin((global_position.x * 0.173 + global_position.y * 0.291) * 12.9898) * 43758.5453, 1.0)


func _draw() -> void:
	if radius <= 0.0 or star_size <= 0.0:
		return
	var tint := _tint()
	var seed := _seed()
	var r := radius * star_size
	var width := maxf(1.0, radius * stroke)
	var pulse := 1.0 - pulse_depth * (0.5 + 0.5 * cos(TAU * (_time * pulse_hz + seed)))
	var glow := Emissive.at(tint, Emissive.stops(glow_tier) * pulse)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(tint.darkened(0.35), 0.9), width)
	var spin := TAU * (_time * spin_hz + seed)
	var pts := PackedVector2Array()
	# Every second vertex of a pentagon, closed: the five-pointed star.
	for i in 6:
		pts.append(Vector2.from_angle(spin - PI / 2.0 + TAU * float(i * 2) / 5.0) * r)
	draw_polyline(pts, glow, width, true)
