@tool
class_name LightArrow
extends Node2D

## Oriented light-arrow visual for ranged-attack projectiles. Glowing
## shaft + arrowhead, tinted by the firing entity's colour. On arrival the
## arrow "sticks" into the target node and fades out over [member hold_seconds]
## + [member fade_seconds].
##
## Visual contract (see [Projectile]):
##   inbound  — `_on_launch()`, `_on_progress(t)`, `_on_arrival()`, and the
##              impact beats `_on_dud()` / `_on_absorbed(gained)` (both
##              optional; the coordinator dispatches them off the landed hit)
##   outbound — [signal finished] (fired once the post-arrival fade completes)

signal finished

const TINT = Color(1.0, 0.9, 0.6, 1.0)
## The heal green the floaters already speak — one colour for "the defender
## gained", whether it is a number or an arrow.
const _FloaterStyles := preload("res://ui/floating_number_layer/floater_styles.gd")

## Set by the coordinator before the projectile launches. Read at draw time.
## Carries the attacker's identity colour (or the fallback above) — the
## per-instance variation the rendering-performance rule wants on `modulate`/
## an export, never a per-node shader uniform (this visual has no shader).
@export var tint: Color = TINT
@export var shaft_length: float = 18.0
@export var shaft_width: float = 2.0
@export var head_length: float = 8.0
@export var head_width: float = 6.0
@export var glow_radius: float = 12.0
## How long the arrow stays at full opacity after sticking.
@export var hold_seconds: float = 0.35
## Fade-out duration after [member hold_seconds] elapses.
@export var fade_seconds: float = 0.4
## Radius the absorb ring expands to around the tip, as a multiple of
## [member glow_radius]. The held (neutral) glint uses half the spread.
@export var absorb_ring_scale: float = 1.6
@export var absorb_ring_width: float = 1.5

var _alpha: float = 1.0
var _arrived: bool = false
var _done_emitted: bool = false
var _dud: bool = false
## Set by `_on_absorbed`; [member _gained] then picks gain-green vs neutral.
var _absorbed: bool = false
var _gained: bool = false
## 0 → 1 over [member hold_seconds] once absorbed; drives the ring.
var _pulse: float = 0.0


func _ready() -> void:
	# Idle until launched; nothing to draw before the coordinator wires up.
	queue_redraw()


func _on_launch() -> void:
	queue_redraw()


func _on_progress(_t: float) -> void:
	queue_redraw()


## #503 — this shot's landing was VETOED at arrival (the target was already
## dead or no longer hostile by the time the arrow got there). Part of the
## visual contract alongside `_on_arrival()`: the coordinator calls it at
## touchdown when [member HitInstance.gated] is set. The arrow still arrives
## on schedule; it just lands spent, and no damage number follows it because
## the applier never called `take_damage`.
func _on_dud() -> void:
	_dud = true
	queue_redraw()


## #753 — this shot landed and changed nothing hostile. [param gained] true:
## mitigation went below zero and the hit HEALED the defender — the arrow
## turns heal-green and a bright ring pulses out of the tip, a gain for them.
## False: mitigated to exactly zero — the arrow goes steel off-white with a
## small dim glint ring, "their armour held". Both stay distinct from the dud
## (grey, INERT, no ring), which means the shot never landed at all. Only the
## impact differs; the flight was drawn exactly as any other arrow's.
func _on_absorbed(gained: bool) -> void:
	_absorbed = true
	_gained = gained
	var tween := create_tween()
	tween.tween_property(self, "_pulse", 1.0, hold_seconds + fade_seconds)
	queue_redraw()


func _on_arrival() -> void:
	if _arrived:
		return
	_arrived = true
	# Hold at full alpha, then fade. Tween drives _alpha and triggers redraw
	# each step via the property setter (we don't need a setter — manual
	# queue_redraw on the tween step does the job).
	var tween := create_tween()
	tween.tween_interval(hold_seconds)
	tween.tween_property(self, "_alpha", 0.0, fade_seconds)
	tween.tween_callback(func() -> void:
		if _done_emitted:
			return
		_done_emitted = true
		finished.emit())
	# Keep the redraw cadence going while alpha changes.
	set_process(true)


func _process(_delta: float) -> void:
	if _arrived:
		queue_redraw()


# Local space: the projectile rotates the parent so +X = forward.
# Arrow points along +X with the tail behind (negative X).
func _draw() -> void:
	var a := clampf(_alpha, 0.0, 1.0)
	# Emissive tiers over the (possibly per-instance) tint, not a hand-picked
	# `.lightened()` — VALUE for the shaft/head, a dimmer LABEL step for the
	# halo so the coverage-heavy glow doesn't blow out at scale.
	var base := Color(tint.r, tint.g, tint.b, tint.a * a)
	if _dud:
		# A spent arrow reads as spent, not merely dimmer: pull most of the
		# saturation out toward luminance, then sit at INERT so it is still
		# visible but cannot bloom. Same language as a spike-popped blade
		# vertex dimming (docs/domain/attack-timeline.md, "Ranged").
		var lum := base.get_luminance()
		base = Color(lum, lum, lum, base.a).lerp(base, 0.25)
	if _absorbed:
		# Replace the attacker's identity outright: at the impact the arrow
		# speaks for what happened to the DEFENDER, not who fired it.
		var hue := _FloaterStyles.COLOR_HEAL if _gained else Emissive.NEUTRAL
		base = Color(hue.r, hue.g, hue.b, base.a)
	var col := Emissive.at(base, Emissive.INERT if _dud else Emissive.VALUE)
	var glow := Emissive.at(Color(tint.r, tint.g, tint.b, tint.a * a * 0.25), Emissive.LABEL)
	if not _arrived:
		# Glow halo around the tip.
		draw_circle(Vector2.ZERO, glow_radius, glow)
	# Shaft: from (-shaft_length, 0) back to (0,0) tip.
	var tail := Vector2(-shaft_length-head_length, 0.0)
	draw_line(tail, Vector2(-head_length, 0.0), col, shaft_width, true)
	# Arrowhead triangle, point at origin, base at (-head_length, ±head_width/2).
	var p0 := Vector2.ZERO
	var p1 := Vector2(-head_length, head_width * 0.5)
	var p2 := Vector2(-head_length, -head_width * 0.5)
	draw_colored_polygon(PackedVector2Array([p0, p1, p2]), col)
	if _absorbed:
		_draw_absorb_ring(base)


## The absorb beat's ring at the tip: expands with [member _pulse] and thins
## out as it goes. Gain = heal green at ALERT (loud — the defender GOT
## something); held = neutral at LABEL, half the spread (a glint, not news).
func _draw_absorb_ring(base: Color) -> void:
	var p := clampf(_pulse, 0.0, 1.0)
	var spread := absorb_ring_scale * (1.0 if _gained else 0.5)
	var r := glow_radius * lerpf(0.4, spread, p)
	var ring := Color(base.r, base.g, base.b, base.a * (1.0 - p))
	var tier := Emissive.ALERT if _gained else Emissive.LABEL
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Emissive.at(ring, tier), absorb_ring_width, true)
