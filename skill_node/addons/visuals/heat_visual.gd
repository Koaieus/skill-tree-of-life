@tool
class_name HeatVisual
extends AddonVisual

## The Heat addon's drawing: embers licking up off the carrier's rim. Each of
## [member ember_count] embers rises from a point on the upper rim, flickers and
## fades — one [method _draw] pass for all of them, never a node per ember.
## Colour is the parent addon's identity tint; the embers glow on a named
## [enum Emissive.Tier]. Animation is a pure function of time and a per-carrier
## seed, redrawn at [member redraw_hz] and only while visible.

const _FALLBACK_TINT := Color(1.0, 0.45, 0.15)

## Embers alive at once on one carrier — the hard per-node cap.
@export_range(1, 24, 1) var ember_count: int = 7:
	set(value):
		ember_count = value
		queue_redraw()
## An ember's radius at birth, as a fraction of the carrier's radius.
@export_range(0.02, 0.3, 0.01) var ember_size: float = 0.08:
	set(value):
		ember_size = value
		queue_redraw()
## Ember lives per second.
@export_range(0.05, 3.0, 0.05) var rise_speed: float = 0.7:
	set(value):
		rise_speed = value
		queue_redraw()
## How far an ember climbs before it fades, × the carrier's radius.
@export_range(0.0, 2.0, 0.05) var rise_height: float = 0.8:
	set(value):
		rise_height = value
		queue_redraw()
## Glow tier of the embers (`.claude/rules/hdr-color.md`).
@export var ember_tier: Emissive.Tier = Emissive.Tier.VALUE:
	set(value):
		ember_tier = value
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


static func _hash(x: float) -> float:
	return fposmod(sin(x * 12.9898) * 43758.5453, 1.0)


func _draw() -> void:
	if radius <= 0.0 or ember_count <= 0:
		return
	var glow := Emissive.at(_tint(), Emissive.stops(ember_tier))
	var seed := _hash(global_position.x * 0.137 + global_position.y * 0.311)
	var size := radius * ember_size
	for i in ember_count:
		var h := _hash(float(i) + seed * 97.0)
		# Born on the upper rim, spread over ±70° of straight up.
		var theta := -PI * 0.5 + deg_to_rad(140.0) * (h - 0.5)
		var life := fposmod(_time * rise_speed * (0.7 + 0.6 * h) + h, 1.0)
		var base := Vector2.from_angle(theta) * radius
		var sway := sin((_time * 3.0 + h * TAU)) * size * 0.8
		var center := base + Vector2(sway, -radius * rise_height * life)
		var r := size * (1.0 - 0.7 * life)
		draw_circle(center, r, Color(glow, 0.85 * (1.0 - life)))
