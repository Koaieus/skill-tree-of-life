@tool
class_name AshfallVisual
extends AddonVisual

## Ashfall's drawing: a crumbling rim shedding ash. The carrier's rim is a ring
## of [member rim_segments] arcs, each flaking away and re-forming on its own
## phase; [member flake_count] ash flakes break off the rim and drift DOWN
## (screen +y) with a slow sideways sway, greying and fading as they fall —
## Wither's arrow look (dry ash off the trail) on a standing node. One
## [method _draw] pass for all of it, never a node per flake. Colour is the
## parent addon's identity tint; the rim embers glow on a named
## [enum Emissive.Tier].
##
## Animation is a pure function of time and a per-carrier seed, redrawn at
## [member redraw_hz] and only while visible (a board draws a few hundred
## carriers; the cost is CPU draw-list rebuilds).

const _FALLBACK_TINT := Color(0.62, 0.55, 0.42)
## The grey an ash flake fades toward as it falls.
const _ASH := Color(0.55, 0.53, 0.5)

## Ash flakes alive at once on one carrier — the hard per-node cap.
@export_range(1, 24, 1) var flake_count: int = 10:
	set(value):
		flake_count = value
		queue_redraw()
## A flake's size, as a fraction of the carrier's radius.
@export_range(0.02, 0.3, 0.01) var flake_size: float = 0.07:
	set(value):
		flake_size = value
		queue_redraw()
## Flake lives per second (one life = break off, fall, fade).
@export_range(0.05, 2.0, 0.05) var fall_speed: float = 0.3:
	set(value):
		fall_speed = value
		queue_redraw()
## How far below its break-off point a flake falls, x the carrier's radius.
@export_range(0.0, 2.0, 0.05) var fall_distance: float = 0.9:
	set(value):
		fall_distance = value
		queue_redraw()
## Sideways sway of a falling flake, x the carrier's radius.
@export_range(0.0, 0.5, 0.01) var sway: float = 0.12:
	set(value):
		sway = value
		queue_redraw()
## Arcs the crumbling rim is broken into.
@export_range(3, 24, 1) var rim_segments: int = 9:
	set(value):
		rim_segments = value
		queue_redraw()
## Glow tier of the rim's embers (`.claude/rules/hdr-color.md`); the ash
## itself stays a plain colour.
@export var ember_tier: Emissive.Tier = Emissive.Tier.LABEL:
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


## Stable per-carrier offset so neighbouring carriers never shed in step.
func _seed() -> float:
	return _hash(global_position.x * 0.173 + global_position.y * 0.293)


static func _hash(x: float) -> float:
	return fposmod(sin(x * 12.9898) * 43758.5453, 1.0)


func _draw() -> void:
	if radius <= 0.0:
		return
	var tint := _tint()
	var ember := Emissive.at(tint, Emissive.stops(ember_tier))
	var seed := _seed()
	_draw_rim(tint, ember, seed)
	_draw_flakes(tint, seed)


## The crumbling rim: each arc thins to nothing and re-forms on its own phase.
func _draw_rim(tint: Color, ember: Color, seed: float) -> void:
	var span := TAU / float(rim_segments)
	var width := maxf(1.0, radius * 0.08)
	for i in rim_segments:
		var h := _hash(float(i) * 3.1 + seed * 53.0)
		var phase := fposmod(_time * 0.25 * (0.7 + 0.6 * h) + h, 1.0)
		var whole := 1.0 - phase
		var start := span * float(i) + span * 0.08
		var length := span * 0.84 * whole
		if length <= 0.01:
			continue
		draw_arc(Vector2.ZERO, radius * 1.04, start, start + length, 6,
				Color(tint, 0.85 * whole), width * whole)
		# The crumbling end glows as an ember just before it breaks off.
		draw_circle(Vector2.from_angle(start + length) * radius * 1.04,
				width * 0.6 * whole, Color(ember, 0.7 * whole))


## The flakes: break off the rim, fall straight down with a sway, grey and fade.
func _draw_flakes(tint: Color, seed: float) -> void:
	if flake_count <= 0:
		return
	var size := radius * flake_size
	for i in flake_count:
		var h := _hash(float(i) + seed * 97.0)
		var theta := TAU * (float(i) + h * 0.8) / float(flake_count)
		var life := fposmod(_time * fall_speed * (0.8 + 0.4 * h) + h, 1.0)
		var from := Vector2.from_angle(theta) * radius * 1.04
		var drift := Vector2(sin((life * 2.0 + h) * TAU) * sway * radius,
				life * fall_distance * radius)
		var center := from + drift
		var colour := tint.lerp(_ASH, life)
		var s := size * (1.0 - 0.4 * life)
		# A tumbling flake: a thin quad whose width breathes with its spin.
		var spin := (life * 3.0 + h) * TAU
		var along := Vector2.from_angle(spin) * s
		var across := Vector2.from_angle(spin + PI * 0.5) * s * (0.35 + 0.25 * absf(sin(spin)))
		draw_colored_polygon(PackedVector2Array([center + along, center + across,
				center - along, center - across]), Color(colour, 0.8 * (1.0 - life)))
