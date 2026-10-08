@tool
class_name ToxinVisual
extends AddonVisual

## The toxin's drawing: froth on the carrier's rim. Each of [member bubble_count]
## bubbles swells on the rim while drifting outward, then pops into a green gas
## puff that widens and fades — one [method _draw] pass for all of them, never
## a node per bubble (a level draws a few hundred carriers). Colour is the
## parent addon's identity tint; the gas glows on a named [enum Emissive.Tier].
##
## Animation is a pure function of time and a per-carrier seed, redrawn at
## [member redraw_hz] rather than every frame, and only while visible — the
## cost of a board full of toxins is CPU draw-list rebuilds, so it is capped.

const _FALLBACK_TINT := Color(0.45, 0.95, 0.3)
## Fraction of a bubble's life spent as froth; the rest is the gas puff.
const _FROTH_SHARE := 0.6

## Bubbles alive at once on one carrier — the hard per-node cap.
@export_range(1, 24, 1) var bubble_count: int = 8:
	set(value):
		bubble_count = value
		queue_redraw()
## A grown bubble's radius, as a fraction of the carrier's radius.
@export_range(0.02, 0.3, 0.01) var bubble_size: float = 0.09:
	set(value):
		bubble_size = value
		queue_redraw()
## Bubble lives per second (one life = swell, pop, puff, fade).
@export_range(0.05, 2.0, 0.05) var rise_speed: float = 0.35:
	set(value):
		rise_speed = value
		queue_redraw()
## How far beyond the rim a bubble and its puff drift, × the carrier's radius.
@export_range(0.0, 1.0, 0.05) var rise_distance: float = 0.45:
	set(value):
		rise_distance = value
		queue_redraw()
## How wide a gas puff spreads at its fade, × a grown bubble's radius.
@export_range(1.0, 5.0, 0.1) var puff_spread: float = 2.6:
	set(value):
		puff_spread = value
		queue_redraw()
## Glow tier of the gas puffs (`.claude/rules/hdr-color.md`); the froth itself
## stays a plain colour.
@export var gas_tier: Emissive.Tier = Emissive.Tier.LABEL:
	set(value):
		gas_tier = value
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


## Stable per-carrier offset so neighbouring toxins never pulse in step.
func _seed() -> float:
	return _hash(global_position.x * 0.137 + global_position.y * 0.311)


static func _hash(x: float) -> float:
	return fposmod(sin(x * 12.9898) * 43758.5453, 1.0)


func _draw() -> void:
	if radius <= 0.0 or bubble_count <= 0:
		return
	var tint := _tint()
	var gas := Emissive.at(tint, Emissive.stops(gas_tier))
	var seed := _seed()
	var size := radius * bubble_size
	for i in bubble_count:
		var h := _hash(float(i) + seed * 97.0)
		var theta := TAU * (float(i) + h * 0.8) / float(bubble_count)
		var life := fposmod(_time * rise_speed * (0.8 + 0.4 * h) + h, 1.0)
		var radial := Vector2.from_angle(theta)
		var out := radius * (1.0 + rise_distance * life)
		var center := radial * out
		if life < _FROTH_SHARE:
			var grow := life / _FROTH_SHARE
			var r := size * (0.35 + 0.65 * grow)
			draw_circle(center, r, Color(tint, 0.35))
			draw_arc(center, r, 0.0, TAU, 12, Color(tint, 0.9), maxf(1.0, r * 0.25))
		else:
			var fade := (life - _FROTH_SHARE) / (1.0 - _FROTH_SHARE)
			var r := size * lerpf(1.0, puff_spread, fade)
			draw_circle(center, r, Color(gas, 0.45 * (1.0 - fade)))
