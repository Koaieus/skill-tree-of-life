@tool
class_name LightArrow
extends Node2D

## Oriented light-arrow visual for ranged-attack projectiles. Glowing
## shaft + arrowhead, tinted by the firing entity's colour. On arrival the
## arrow "sticks" into the target node and fades out over [member hold_seconds]
## + [member fade_seconds].
##
## Visual contract (see [Projectile]):
##   inbound  — `_on_launch()`, `_on_progress(t)`, `_on_arrival()`
##   outbound — [signal finished] (fired once the post-arrival fade completes)

signal finished

const TINT = Color(1.0, 0.9, 0.6, 1.0)

## Set by the coordinator before the projectile launches. Read at draw time.
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

var _alpha: float = 1.0
var _arrived: bool = false
var _done_emitted: bool = false


func _ready() -> void:
	# Idle until launched; nothing to draw before the coordinator wires up.
	queue_redraw()


func _on_launch() -> void:
	queue_redraw()


func _on_progress(_t: float) -> void:
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
	var col := Color(tint.r, tint.g, tint.b, tint.a * a).lightened(0.5)
	var glow := Color(tint.r, tint.g, tint.b, tint.a * a * 0.25)
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
