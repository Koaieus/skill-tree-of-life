@tool
class_name RiderBlastLayer
extends Node2D

## The generic rider layer on a board blast: a thinner ring in the rider's own
## [member Identity.tint], trailing the explosive ring ([BlastVisual]) by
## [member lag] per layer and landing with it. [BlastVisual] hands it
## [member rider], [member layer], [member radius] and [member duration] at
## play; a row with its own look authors [member Aspect.blast_layer] instead.

## Seconds behind the main ring, per layer (layer 0 trails by one lag).
@export_range(0.0, 0.3, 0.005) var lag: float = 0.06:
	set(value):
		lag = maxf(value, 0.0)
		queue_redraw()
## Glow tier of the rider's hue.
@export var emissive_tier: Emissive.Tier = Emissive.Tier.VALUE:
	set(value):
		emissive_tier = value
		queue_redraw()
## Stroke width in px — thinner than the main ring.
@export_range(0.5, 12.0, 0.1) var thickness: float = 1.2:
	set(value):
		thickness = value
		queue_redraw()
## The rider whose hue this layer carries.
@export var rider: Identity = null:
	set(value):
		rider = value
		queue_redraw()
## The ring's final radius in px — the blast's reach.
@export_range(0.0, 2000.0, 1.0) var radius: float = 120.0:
	set(value):
		radius = maxf(value, 0.0)
		queue_redraw()
## The main ring's sweep time; this layer lands when it does.
@export_range(0.05, 2.0, 0.01) var duration: float = 0.35
## Index among the blast's layers: the lag stacks per layer.
var layer: int = 0

## Seconds since play; INF at rest (the scene opened alone) shows the full ring.
var _elapsed: float = INF


## Laid by a [BlastVisual] it sweeps from its parent's play; alone it rests.
func _ready() -> void:
	if get_parent() is BlastVisual:
		_elapsed = 0.0
	set_process(_elapsed < duration)


## The layer's colour at full strength: the rider's tint at [member emissive_tier].
func color() -> Color:
	var base := rider.tint if rider != null else Color.WHITE
	return Emissive.tint(base, Emissive.stops(emissive_tier))


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= duration:
		set_process(false)


func _draw() -> void:
	if radius <= 0.0:
		return
	var delay := minf(lag * float(layer + 1), duration * 0.9)
	var t := clampf((_elapsed - delay) / maxf(duration - delay, 0.001), 0.0, 1.0)
	if t <= 0.0:
		return
	var sweep := 1.0 - pow(1.0 - t, 3.0)
	var fade := 1.0 if t < 0.5 else 1.0 - (t - 0.5) * 2.0
	var c := color()
	if _elapsed < duration:
		c.a *= clampf(fade, 0.0, 1.0)
	draw_arc(Vector2.ZERO, radius * maxf(sweep, 0.02), 0.0, TAU, 96, c, thickness, true)
