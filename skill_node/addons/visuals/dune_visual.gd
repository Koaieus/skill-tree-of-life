@tool
class_name DuneVisual
extends AddonVisual

## The Dune's drawing: a drift of sand grains circling just outside the
## carrier's rim, and every [member puff_period] seconds a puff — the grains
## billow outward in a soft cloud and settle back. One [method _draw] pass for
## every grain, never a node per grain (a level draws a few hundred carriers).
## Colour is the parent addon's identity tint (Blindness's grey-lavender); only
## the puff's haze glows, on a named [enum Emissive.Tier].
##
## Animation is a pure function of time and a per-carrier seed, redrawn at
## [member redraw_hz] rather than every frame, and only while visible.

const _FALLBACK_TINT := Color(0.7, 0.66, 0.8)
## The sand's base colour the tint is mixed toward, so grains read as grit.
const _SAND := Color(0.78, 0.72, 0.6)

## Grains in the drift — the hard per-node cap.
@export_range(1, 48, 1) var grain_count: int = 18:
	set(value):
		grain_count = value
		queue_redraw()
## A grain's radius, as a fraction of the carrier's radius.
@export_range(0.01, 0.2, 0.005) var grain_size: float = 0.035:
	set(value):
		grain_size = value
		queue_redraw()
## The drift band's mid radius, × the carrier's radius.
@export_range(1.0, 2.0, 0.01) var drift_radius: float = 1.15:
	set(value):
		drift_radius = value
		queue_redraw()
## The drift's circling speed, in turns per second.
@export_range(0.0, 0.5, 0.01) var drift_speed: float = 0.04:
	set(value):
		drift_speed = value
		queue_redraw()
## Seconds between puffs.
@export_range(0.5, 10.0, 0.1) var puff_period: float = 3.0:
	set(value):
		puff_period = value
		queue_redraw()
## Fraction of a period the puff lasts (billow out, then settle).
@export_range(0.05, 1.0, 0.05) var puff_share: float = 0.45:
	set(value):
		puff_share = value
		queue_redraw()
## How far a puff throws the grains beyond the drift, × the carrier's radius.
@export_range(0.0, 1.5, 0.05) var puff_reach: float = 0.55:
	set(value):
		puff_reach = value
		queue_redraw()
## Glow tier of the puff's haze (`.claude/rules/hdr-color.md`); the grains
## themselves stay a plain colour.
@export var haze_tier: Emissive.Tier = Emissive.Tier.LABEL:
	set(value):
		haze_tier = value
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


## Stable per-carrier offset so neighbouring dunes never puff in step.
func _seed() -> float:
	return _hash(global_position.x * 0.191 + global_position.y * 0.277)


static func _hash(x: float) -> float:
	return fposmod(sin(x * 12.9898) * 43758.5453, 1.0)


## 0 at rest, rising to 1 at the puff's height and back to 0 as it settles.
func _puff(seed: float) -> float:
	var phase := fposmod(_time / puff_period + seed, 1.0)
	if phase >= puff_share:
		return 0.0
	return sin(PI * phase / puff_share)


func _draw() -> void:
	if radius <= 0.0 or grain_count <= 0:
		return
	var tint := _tint()
	var grit := _SAND.lerp(tint, 0.6)
	var seed := _seed()
	var puff := _puff(seed)
	var size := radius * grain_size
	if puff > 0.0:
		var haze := Emissive.at(tint, Emissive.stops(haze_tier))
		var haze_r := radius * (drift_radius + puff_reach * puff * 0.6)
		draw_arc(Vector2.ZERO, haze_r, 0.0, TAU, 32,
				Color(haze, 0.25 * puff), radius * 0.25 * puff)
	for i in grain_count:
		var h := _hash(float(i) + seed * 97.0)
		var theta := TAU * (float(i) + h * 0.7) / float(grain_count) \
				+ _time * drift_speed * TAU * (0.7 + 0.6 * h)
		var band := radius * (drift_radius + 0.1 * (h - 0.5))
		var out := band + radius * puff_reach * puff * (0.5 + h)
		var center := Vector2.from_angle(theta) * out
		var r := size * (0.6 + 0.8 * h) * (1.0 + 0.5 * puff)
		draw_circle(center, r, Color(grit, 0.85 - 0.45 * puff))
