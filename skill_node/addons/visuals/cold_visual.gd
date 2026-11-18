@tool
class_name ColdVisual
extends AddonVisual

## The Cold addon's drawing: rime crystals standing off the carrier's rim. Each
## of [member crystal_count] crystals is a thin six-armed star on the rim,
## glinting in turn — one [method _draw] pass for all of them, never a node per
## crystal. Colour is the parent addon's identity tint; the glint glows on a
## named [enum Emissive.Tier]. Animation is a pure function of time and a
## per-carrier seed, redrawn at [member redraw_hz] and only while visible.

const _FALLBACK_TINT := Color(0.3, 0.7, 0.75)

## Crystals on one carrier.
@export_range(1, 16, 1) var crystal_count: int = 5:
	set(value):
		crystal_count = value
		queue_redraw()
## A crystal's arm length, as a fraction of the carrier's radius.
@export_range(0.02, 0.4, 0.01) var crystal_size: float = 0.14:
	set(value):
		crystal_size = value
		queue_redraw()
## Glints per second, travelling crystal to crystal.
@export_range(0.0, 3.0, 0.05) var glint_speed: float = 0.4:
	set(value):
		glint_speed = value
		queue_redraw()
## Glow tier of a glinting crystal (`.claude/rules/hdr-color.md`).
@export var glint_tier: Emissive.Tier = Emissive.Tier.VALUE:
	set(value):
		glint_tier = value
		queue_redraw()
## Redraw rate cap, in Hz.
@export_range(5.0, 60.0, 1.0) var redraw_hz: float = 15.0

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
	if radius <= 0.0 or crystal_count <= 0:
		return
	var tint := _tint()
	var glow := Emissive.at(tint, Emissive.stops(glint_tier))
	var seed := _hash(global_position.x * 0.137 + global_position.y * 0.311)
	var arm := radius * crystal_size
	var lit := fposmod(_time * glint_speed + seed, 1.0) * crystal_count
	for i in crystal_count:
		var theta := TAU * (float(i) + seed) / float(crystal_count)
		var center := Vector2.from_angle(theta) * radius
		# A glint rides from crystal to crystal; it peaks on one at a time.
		var near := clampf(1.0 - absf(lit - float(i) - 0.5) * 2.0, 0.0, 1.0)
		var colour := tint.lerp(glow, near)
		colour.a = 0.7 + 0.3 * near
		var spin := theta + _hash(float(i) + seed * 31.0) * PI
		for k in 3:
			var d := Vector2.from_angle(spin + PI * float(k) / 3.0) * arm
			draw_line(center - d, center + d, colour, maxf(1.0, arm * 0.18))
