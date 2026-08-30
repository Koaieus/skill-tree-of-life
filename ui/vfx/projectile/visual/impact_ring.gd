@tool
class_name ImpactRing
extends Node2D

## The punctuation primitive (#670 P2) — [CancelDissipate] generalized into the
## one place the whole spell book gets its impact and its crit grammar from.
##
## [b]It owns #663 D6's uniform crit grammar, and it owns it once.[/b] Tier 1 is
## a single ring at [constant Emissive.ALERT]; tier 2+ adds a second concentric
## ring plus a [b]single-frame[/b] [constant Emissive.PEAK] core flash. That
## makes combat the only place PEAK ever appears, which is what makes tier 2
## unmistakable. The eight per-spell units get their crit look by [i]configuring
## this scene[/i], never by authoring a second one — so "where it fired" (leaf /
## convergence / self-loop) reads as placement rather than as three different
## effects.
##
## [member direction] is the other axis, and it is what tells an arrival apart
## from a gather:
##   [constant Direction.OUT] — expands away from the node. Impact.
##   [constant Direction.IN]  — contracts onto the node. Absorb: a heal landing,
##                              or Resonator's branches converging.
##
## Visual contract (see [Projectile]):
##   inbound  — `_on_arrival()`, `_on_crit(tier)`, `_on_context(entry)`
##              (NOT `_on_launch()` — see below)
##   outbound — [signal finished]
##
## It is also usable standalone as a `cancel_visual` — instantiate it at the
## target node and it plays on `_ready`, exactly as [CancelDissipate] does.

signal finished

enum Direction {
	## Expanding — the default. An impact pushing outward from the node.
	OUT,
	## Contracting onto the node. Reads as absorb / gather, which is what
	## distinguishes a heal arrival and a convergence from a hit.
	IN,
}

## Radii of the concentric rings the crit grammar draws, as multiples of
## [member radius]. Index 0 is the primary ring, index 1 the tier-2 companion.
const RING_SCALES: Array[float] = [1.0, 0.58]

## Ring count the grammar produces at each crit tier. Index = tier, clamped.
const CRIT_RING_COUNT: Array[int] = [1, 1, 2]

## Identity colour, stamped by the coordinator the same way [member
## BoltBody.tint] is. A crit overrides it with damage-red (or, for a critical
## heal, #663 D5's documented gold carve-out — a caller sets [member
## crit_color] for that rather than this class hard-coding a second palette).
@export var tint: Color = Color.WHITE

## 0 = no crit. 1 = one ring at ALERT. 2+ = double ring + a one-frame PEAK core
## flash. Settable in the inspector so the playground can render all three
## states side by side; `_on_crit(tier)` sets it at runtime.
@export_range(0, 3, 1) var crit_tier: int = 0:
	set(value):
		crit_tier = maxi(0, value)
		# A coordinator may stamp the tier AFTER instantiating the ring at its
		# target, by which point a standalone ring is already playing — so the
		# flash arms from whichever of the two happens second.
		if _playing:
			_arm_flash()
		_rebuild()

## Rings drawn on a NON-crit impact. The crit grammar overrides this upward;
## it never overrides it downward, so a spell that wants two resting rings
## keeps them.
@export_range(1, 3, 1) var ring_count: int = 1:
	set(value):
		ring_count = maxi(1, value)
		_rebuild()

## Ellipse squash. 1.0 = a circle; below 1.0 flattens the ring along local Y,
## which reads as a ring lying on the board rather than facing the camera.
@export_range(0.15, 1.0, 0.01) var squash: float = 1.0

## OUT expands, IN contracts. See [enum Direction].
@export var direction: Direction = Direction.OUT

## Starting radius for [constant Direction.OUT] / ending radius for
## [constant Direction.IN], in world pixels.
@export_range(1.0, 128.0, 0.5) var radius: float = 12.0

## The far end of the sweep — where OUT expands to, where IN starts from.
@export_range(1.0, 256.0, 0.5) var expand_radius: float = 30.0

## Stroke width in world pixels.
@export_range(0.5, 12.0, 0.1) var thickness: float = 2.0

@export_range(0.05, 2.0, 0.01) var duration: float = 0.35

## Resting emissive tier for a non-crit ring. A crit lifts to
## [constant Emissive.ALERT] — reserve it, or nothing reads as loud.
@export_range(0.0, 3.0, 0.05) var emissive_tier: float = Emissive.VALUE

## Colour a crit retints to. Damage-red by default; #663 D5's critical-heal
## gold is authored by the Healing Beam unit setting this, not by a second
## code path here.
@export var crit_color: Color = Color.ORANGE_RED

## Set true once the tier-2 core flash has been drawn. It is a SINGLE frame by
## construction — `_draw` clears it — so a test can assert the flash happened
## without racing a tween.
var peak_flash_fired: bool = false

var _t: float = 0.0
var _playing: bool = false
var _done_emitted: bool = false
## True only for the one frame the PEAK core flash is drawn on.
var _flash_pending: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	# Standalone use (a `cancel_visual`, or the playground) plays immediately,
	# exactly as [CancelDissipate] does.
	#
	# Under a [Projectile] it must NOT: the projectile instantiates its visual
	# at LAUNCH, so an autoplay here would run the whole ring out and
	# `queue_free` this node a full flight before impact — and `Projectile`
	# then `await`s `finished` on a freed node and hangs the BattleSystem chain
	# behind it. So the parent decides, which needs no new export and no
	# coordinator cooperation.
	if get_parent() is Projectile:
		return
	play()


# ---------------------------------------------------------------- duck contract


## Deliberately absent from the inbound contract: `_on_launch()`. This is
## punctuation — it fires when something lands, never when something sets off.
## A `play()` here would put the ring at the origin node a whole flight early.


func _on_arrival() -> void:
	play()


func _on_crit(tier: int) -> void:
	crit_tier = tier


## Typed [Variant] on purpose — #543's `ScheduleEntry` does not exist yet and a
## typed parameter would refuse to parse. Reads `convergence_count` when it is
## offered, so Resonator's gather ring widens with the number of branches that
## actually met; absent, the ring is its authored size.
func _on_context(entry: Variant) -> void:
	if entry == null:
		return
	var count: float = VfxContext.read_float(entry, &"convergence_count", -1.0)
	if count > 1.0:
		expand_radius *= 1.0 + 0.12 * (count - 1.0)


# ------------------------------------------------------------------- internals


## Number of concentric rings this ring will actually draw — the crit grammar
## resolved. The per-spell units and the tests read this rather than
## re-deriving the tier table.
func active_ring_count() -> int:
	return maxi(ring_count, CRIT_RING_COUNT[clampi(crit_tier, 0, CRIT_RING_COUNT.size() - 1)])


## True when this ring's tier earns the single-frame PEAK core flash — tier 2
## and up, and nothing else in the game.
func has_peak_flash() -> bool:
	return crit_tier >= 2


func play() -> void:
	if _playing or _done_emitted:
		return
	_playing = true
	_arm_flash()
	_t = 0.0
	set_process(true)
	var tween := create_tween()
	tween.tween_property(self, ^"_t", 1.0, duration)
	tween.tween_callback(_emit_finished)


## Latched from the TIER, not from a draw: the flash is a fact about the crit,
## and a headless test must be able to see it without a real frame. Idempotent,
## and it never un-arms — a ring whose tier drops back to 0 mid-play has already
## earned its one frame.
func _arm_flash() -> void:
	if not has_peak_flash():
		return
	_flash_pending = true
	peak_flash_fired = true


func _process(_delta: float) -> void:
	queue_redraw()


func _rebuild() -> void:
	if is_inside_tree():
		queue_redraw()


func _emit_finished() -> void:
	if _done_emitted:
		return
	_done_emitted = true
	_playing = false
	set_process(false)
	finished.emit()
	queue_free()


## Current sweep radius. OUT runs `radius → expand_radius`; IN runs the sweep
## backwards, which is the whole of what makes an absorb read as an absorb.
func current_radius() -> float:
	var k: float = clampf(_t, 0.0, 1.0)
	if direction == Direction.IN:
		return lerpf(expand_radius, radius, k)
	return lerpf(radius, expand_radius, k)


func _ring_color(index: int) -> Color:
	var base: Color = crit_color if crit_tier > 0 else tint
	var tier: float = Emissive.ALERT if crit_tier > 0 else emissive_tier
	var col: Color = Emissive.tint(base, tier)
	# Alpha is the fade channel, colour value is the dimmer — the companion
	# ring is quieter by alpha, not by dropping off the named tier.
	var fade: float = 1.0 - clampf(_t, 0.0, 1.0)
	col.a = base.a * fade * (1.0 if index == 0 else 0.6)
	return col


func _draw() -> void:
	var rings: int = active_ring_count()
	var r: float = current_radius()
	for i in rings:
		var scale_i: float = RING_SCALES[mini(i, RING_SCALES.size() - 1)]
		_draw_ellipse(r * scale_i, _ring_color(i))
	if _flash_pending:
		# ONE frame at PEAK, then never again — an ignition overshoot relaxing
		# back down, never a resting state (docs/domain/hdr-color.md).
		_flash_pending = false
		var flash: Color = Emissive.tint(crit_color, Emissive.PEAK)
		draw_circle(Vector2.ZERO, radius * 0.75, flash)


## `draw_arc` with a uniform scale on the Y axis — a squashed ring is one
## `scale` write, not a second geometry path.
func _draw_ellipse(r: float, col: Color) -> void:
	var points: PackedVector2Array = []
	var segments: int = 32
	for i in segments + 1:
		var a: float = TAU * float(i) / float(segments)
		points.append(Vector2(cos(a) * r, sin(a) * r * squash))
	draw_polyline(points, col, thickness, true)
