@tool
class_name ChargeGlow
extends Node2D

## The splash root's charge-up — the bespoke ring that builds toward the
## allocation BOOM (#734).
##
## [b]Bespoke means bespoke.[/b] Owner, 2026-09-03: [i]"it should ramp up the
## ring. a bespoke effect, not part of the regular skillnodes. just for this one.
## the idea is this: click it, and it starts glowing, until BOOM allocation vfx
## (which is some power needle spike thingy)"[/i] — so nothing here touches
## [NodeVisualsComposite], `rim_ring.gd` or [SkillNode]. It is a sibling ADDED
## alongside the composite by `splash_root_view.tscn`, which is the one move
## Godot offers: an inherited scene may add nodes freely but may not re-point an
## instanced child at a different [PackedScene] (`docs/domain/scene-composition.md`).
##
## [b]Why it is drawn rather than composed.[/b] `RimRing.fill_current` is an
## [int] — a slot dial, not a continuous fill — so there is no existing ring to
## borrow a sweep from. One [method CanvasItem._draw] over three arcs is smaller
## than the scene it would otherwise take, and this node is the only one of its
## kind on screen, so the draw-call arithmetic in
## `.claude/rules/rendering-performance.md` never comes into play.
##
## [b]It owns no clock.[/b] [method set_progress] is driven from 0 to 1 by
## [SplashScreen]'s leg-1 tween — the repo convention for an animated unit
## (`ui/tooltip_fan/addon_item.gd`), and what
## `.claude/rules/presentation-clock.md` requires: the charge never gates the
## BOOM, which fires off the splash's own timer whatever this is doing. The one
## clock this DOES own is the detonation's own settle, which nothing waits on.
##
## [b]Deliberately not guarded by `Engine.is_editor_hint()`[/b] — #578's live tab
## mounts the splash with the hint true, and a blanket early return would leave
## the charge inert exactly where it is meant to be tuned.

## `ui/z_layers.gd` declares no `class_name` — it is the shared z-band index and
## is reached by preload, exactly as [AllocationVFX] reaches it.
const ZLayers = preload("res://ui/z_layers.gd")

## The ramp's endpoints, as named tiers. [constant Emissive.INERT] sits exactly
## at the bloom threshold and never blooms; [constant Emissive.PEAK] is the
## momentary overshoot the needle's own disk already uses. The interpolant
## between them is COMPUTED, which is how a sweep stays tier-authored rather
## than a hand-picked float (`.claude/rules/hdr-color.md`).
const CHARGE_FLOOR := Emissive.INERT
const CHARGE_CEILING := Emissive.PEAK

## How far outside the node's rim the charge ring sits, in world units.
const _RING_GAP := 6.0

## The ring's stroke at full charge, in world units. Scaled by progress, so the
## ring is literally not drawn at `t == 0` — the ramp-in is geometry, never a
## drop in `modulate.a`, because alpha is the fade channel and colour value is
## the dimmer (`.claude/rules/hdr-color.md`).
const _RING_WIDTH := 3.0

## Shimmer: how many arcs circulate, how much of the circle each spans, and the
## angular speed at rest and at full charge. "Accelerating" is the owner's word
## — the arcs speed up as the charge builds, which is what sells a wind-up.
const _SHIMMER_ARCS := 3
const _SHIMMER_SPAN := TAU / 9.0
const _SHIMMER_SPEED_MIN := 1.2
const _SHIMMER_SPEED_MAX := 9.0

## Where in the ramp the flicker starts biting. Late, so it reads as the thing
## straining rather than as a broken ring.
const _FLICKER_START := 0.55

## Where the shockwave ends up, as a multiple of the node radius.
##
## [b]No ceiling is needed here, and that is a property of the choreography.[/b]
## The detonation happens at [constant FrontmatterLayout.TREE_ZOOM] with the root
## in the hero slot — 480px of headroom against a 264px needle. At
## [constant FrontmatterLayout.SPLASH_ZOOM] it would have had to stay under
## ~2.9x the radius to stay on screen; that pose no longer exists at the BOOM.
const _SHOCK_RADIUS_FACTOR := 4.0

## Seconds the shockwave takes to expand and fade, and seconds the charge ring
## takes to settle back to nothing behind it. Both are this node's own; neither
## is awaited by anything.
const _SHOCK_DURATION := 0.45
const _SETTLE_DURATION := 0.3

## The owner's one knob for the flicker (D8) — off in one place, without
## touching the ramp or the shimmer.
@export var charge_flicker: bool = true

## The white flash at the detonation, default OFF (D9). Owner: [i]"dealer's
## choice, 2 sounds coolest, 3 maybe"[/i] — the shockwave is the 2, this is the 3.
@export var charge_flash: bool = false

## Identity, pushed down by [SplashRootView] so this never reaches up to read the
## view it hangs under. See that file for why it is forwarded rather than bound.
var base_color: Color = Emissive.NEUTRAL:
	set(value):
		base_color = value
		_sync_modulate()

var node_radius: float = 32.0:
	set(value):
		node_radius = value
		queue_redraw()

var _progress: float = 0.0
var _stops: float = CHARGE_FLOOR
var _phase: float = 0.0
var _shock: float = 0.0
var _settle: Tween = null


func _ready() -> void:
	# Absolute, and chosen against the two things it sits between: the composite
	# this is a sibling of draws in the relative GRAPH_DEFAULT band and would
	# otherwise cover the glow entirely, while the needle takes
	# `ZLayers.SPELL_VFX` at the BOOM and must still read on top of it. A
	# relative z would inherit the view's own band and lose to whichever sibling
	# happened to be authored later.
	z_as_relative = false
	z_index = ZLayers.SPELL_VFX - 1
	_sync_modulate()


## The charge's position on the splash's clock, 0..1. Pushed every frame by the
## caller that owns the clock; this node never advances it itself.
func set_progress(t: float) -> void:
	_progress = clampf(t, 0.0, 1.0)
	_stops = lerpf(CHARGE_FLOOR, CHARGE_CEILING, _progress)
	_sync_modulate()
	queue_redraw()


## How bright the charge currently reads, in [Emissive] stops. The assertable
## face of the ramp — a test says "the glow is back down at or below
## [constant Emissive.VALUE] once it has detonated" without looking at pixels.
func charge_stops() -> float:
	return _stops


## BOOM. Fires the shockwave and, just as importantly, TAKES THE CHARGE AWAY.
##
## [b]The dismissal is the load-bearing half.[/b] The ring has just been ramped
## to [constant Emissive.PEAK]; left there it would sit permanently super-bright
## behind the root's ordinary lit state, which is a worse artifact than the
## instant-lit snap this whole issue exists to replace. So the charge settles
## back to [constant CHARGE_FLOOR] and stops drawing, while the composite
## underneath takes over at its normal lit reading.
##
## [param instant] collapses both the shockwave and the settle to nothing — what
## [member FrontmatterRoot.reduce_motion] asks for. A player who wanted no motion
## is not asking for a shockwave either.
func detonate(instant: bool = false) -> void:
	if _settle != null and _settle.is_valid():
		_settle.kill()
	_settle = null
	if instant:
		_shock = 0.0
		set_progress(0.0)
		return
	_settle = create_tween()
	_settle.set_parallel(true)
	_settle.tween_method(_set_shock, 0.0, 1.0, _SHOCK_DURATION)
	_settle.tween_method(set_progress, _progress, 0.0, _SETTLE_DURATION)
	_settle.chain().tween_callback(_set_shock.bind(0.0))


func _set_shock(v: float) -> void:
	_shock = v
	queue_redraw()


## The tier write, and the only place `modulate` is authored. White geometry
## times a tier colour IS the tier colour, so the drawing below stays in plain
## [constant Color.WHITE] and every emissive decision lives on this one line.
func _sync_modulate() -> void:
	modulate = Emissive.at(base_color, _stops)


func _process(delta: float) -> void:
	if _progress <= 0.0 and _shock <= 0.0:
		return
	# Accelerating, per the owner: the orbit speed is itself a function of how
	# far the charge has got, so the shimmer visibly winds up rather than
	# spinning at a constant rate under a brightening ring.
	_phase += delta * lerpf(_SHIMMER_SPEED_MIN, _SHIMMER_SPEED_MAX, _progress)
	queue_redraw()


func _draw() -> void:
	if _shock > 0.0:
		_draw_shockwave()
	if _progress <= 0.0:
		return
	var ring_r := node_radius + _RING_GAP
	var width := _RING_WIDTH * _progress * _flicker_factor()
	if width <= 0.0:
		return
	draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 64, Color.WHITE, width, true)
	# The shimmer rides just outside the ring it belongs to, so the two read as
	# one object gathering pace rather than as two concentric animations.
	var shimmer_r := ring_r + width
	for i in _SHIMMER_ARCS:
		var start := _phase + TAU * float(i) / float(_SHIMMER_ARCS)
		draw_arc(
			Vector2.ZERO, shimmer_r, start, start + _SHIMMER_SPAN,
			16, Color.WHITE, width * 0.8, true
		)


## The expanding ring, drawn from the same origin and thinning as it goes. Not
## an [AllocationVFX] spawner: the needle is the game's own and stays reused from
## there, but this shockwave is bespoke to this one beat and has no second caller.
func _draw_shockwave() -> void:
	var r := lerpf(node_radius, node_radius * _SHOCK_RADIUS_FACTOR, _shock)
	var fade := 1.0 - _shock
	var tint := Color(1.0, 1.0, 1.0, fade)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, tint, _RING_WIDTH * fade, true)
	if charge_flash:
		draw_circle(Vector2.ZERO, node_radius * fade, Color(1.0, 1.0, 1.0, fade * 0.5))


## A late, shallow wobble in the ring's stroke. Behind [member charge_flicker] so
## the owner can take it out without touching the ramp or the shimmer, and
## deliberately a function of the shimmer phase rather than of `randf()` — a
## per-frame roll would flicker at the frame rate rather than at a rate anyone
## authored.
func _flicker_factor() -> float:
	if not charge_flicker or _progress < _FLICKER_START:
		return 1.0
	var bite := inverse_lerp(_FLICKER_START, 1.0, _progress)
	return 1.0 - 0.35 * bite * absf(sin(_phase * 3.0))
