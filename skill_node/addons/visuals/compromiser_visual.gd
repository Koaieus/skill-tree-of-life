@tool
class_name CompromiserVisual
extends AddonVisual

## The compromiser's drawing — corruption's arrow vocabulary moved onto the
## carrier's rim: one pustule beating on the rim, and [member blip_count]
## clotted blips that swell in place and pop into a fading ring. One
## [method _draw] pass for all of it, never a node per blip (a level draws a
## few hundred carriers). Colour is the parent addon's identity tint; the
## pustule's core and the pops glow on a named [enum Emissive.Tier].
##
## Animation is a pure function of time and a per-carrier seed, redrawn at
## [member redraw_hz] and only while visible. Every size is a fraction of the
## carrier's radius, so a sibling addon can reuse this look at another scale
## through the knobs alone.

const _FALLBACK_TINT := Color(0.6, 0.25, 0.85)
## Fraction of a blip's life spent swelling; the rest is the pop ring.
const _SWELL_SHARE := 0.75

## The pustule's resting radius, × the carrier's radius.
@export_range(0.05, 0.6, 0.01) var pustule_size: float = 0.2:
	set(value):
		pustule_size = value
		queue_redraw()
## Pustule heartbeats per second.
@export_range(0.1, 4.0, 0.05) var beat_hz: float = 0.9:
	set(value):
		beat_hz = value
		queue_redraw()
## How much a beat swells the pustule, as a fraction of its resting size.
@export_range(0.0, 1.0, 0.05) var beat_depth: float = 0.35:
	set(value):
		beat_depth = value
		queue_redraw()
## Clotted blips alive at once on one carrier — the hard per-node cap.
@export_range(0, 16, 1) var blip_count: int = 5:
	set(value):
		blip_count = value
		queue_redraw()
## A fully swollen blip's radius, × the carrier's radius.
@export_range(0.02, 0.3, 0.01) var blip_size: float = 0.08:
	set(value):
		blip_size = value
		queue_redraw()
## Blip lives per second (one life = swell, pop, fade).
@export_range(0.05, 2.0, 0.05) var blip_speed: float = 0.3:
	set(value):
		blip_speed = value
		queue_redraw()
## How wide a pop ring spreads at its fade, × a swollen blip's radius.
@export_range(1.0, 5.0, 0.1) var pop_spread: float = 2.2:
	set(value):
		pop_spread = value
		queue_redraw()
## Glow tier of the pustule's core and the pop rings
## (`.claude/rules/hdr-color.md`); skins and blips stay plain colour.
@export var glow_tier: Emissive.Tier = Emissive.Tier.LABEL:
	set(value):
		glow_tier = value
		queue_redraw()
## Pustule growth per corruption stack on the carrier's own node, as a
## fraction of [member pustule_size]. 0 = a fixed pustule (the compromiser);
## a sibling that feeds on its own row (the abyssal conduit) swells with it.
@export_range(0.0, 0.5, 0.01) var swell_per_stack: float = 0.0:
	set(value):
		swell_per_stack = value
		queue_redraw()
## Ceiling on that growth, × [member pustule_size].
@export_range(1.0, 4.0, 0.1) var swell_max: float = 2.0:
	set(value):
		swell_max = value
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


## Stable per-carrier offset so neighbouring compromisers never beat in step.
func _seed() -> float:
	return _hash(global_position.x * 0.173 + global_position.y * 0.291)


static func _hash(x: float) -> float:
	return fposmod(sin(x * 12.9898) * 43758.5453, 1.0)


func _draw() -> void:
	if radius <= 0.0:
		return
	var tint := _tint()
	var glow := Emissive.at(tint, Emissive.stops(glow_tier))
	var dark := tint.darkened(0.45)
	var seed := _seed()
	_draw_blips(tint, glow, dark, seed)
	_draw_pustule(tint, glow, dark, seed)


## The pustule's growth from the carrier's own corruption row, read live —
## 1.0 with [member swell_per_stack] at 0 or no node behind the addon.
func _swell() -> float:
	if swell_per_stack <= 0.0:
		return 1.0
	var addon := get_parent()
	var node := addon.get_parent() as SkillNode if addon != null else null
	var host: NodeCombat = node.get_combat() if node != null else null
	if host == null:
		return 1.0
	return minf(1.0 + swell_per_stack * host.get_status_power(&"corruption"), swell_max)


## A lub-dub: a sharp swell, a smaller echo, then rest.
func _beat(phase: float) -> float:
	var lub := exp(-pow((phase - 0.08) * 14.0, 2.0))
	var dub := 0.6 * exp(-pow((phase - 0.28) * 14.0, 2.0))
	return lub + dub


func _draw_pustule(tint: Color, glow: Color, dark: Color, seed: float) -> void:
	if pustule_size <= 0.0:
		return
	var theta := TAU * seed
	var center := Vector2.from_angle(theta) * radius
	var phase := fposmod(_time * beat_hz + seed, 1.0)
	var r := radius * pustule_size * _swell() * (1.0 + beat_depth * _beat(phase))
	draw_circle(center, r, dark)
	draw_circle(center, r * 0.72, Color(tint, 0.9))
	draw_circle(center + Vector2(-r, -r) * 0.18, r * 0.38, glow)
	draw_arc(center, r, 0.0, TAU, 20, Color(dark, 0.95), maxf(1.0, r * 0.14))


func _draw_blips(tint: Color, glow: Color, dark: Color, seed: float) -> void:
	if blip_count <= 0:
		return
	var size := radius * blip_size
	for i in blip_count:
		var h := _hash(float(i) + seed * 89.0)
		# Spread round the rim, clear of the pustule's own arc.
		var theta := TAU * (seed + (float(i) + 0.5 + h * 0.6) / float(blip_count + 1))
		var life := fposmod(_time * blip_speed * (0.8 + 0.4 * h) + h, 1.0)
		var center := Vector2.from_angle(theta) * radius
		if life < _SWELL_SHARE:
			var grow := life / _SWELL_SHARE
			var r := size * (0.25 + 0.75 * grow * grow)
			draw_circle(center, r, Color(dark, 0.85))
			draw_circle(center, r * 0.6, Color(tint, 0.9))
		else:
			var fade := (life - _SWELL_SHARE) / (1.0 - _SWELL_SHARE)
			var r := size * lerpf(1.0, pop_spread, fade)
			draw_arc(center, r, 0.0, TAU, 14, Color(glow, 0.7 * (1.0 - fade)),
					maxf(1.0, size * 0.3 * (1.0 - fade)))
