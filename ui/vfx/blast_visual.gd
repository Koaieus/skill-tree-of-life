@tool
class_name BlastVisual
extends Node2D

## One board blast's ring: centred on the blast's node, sweeping out to the
## sim's own reach ([member radius] — [member BlastMark.reach], never a visual
## guess) and fading, in the [member identity]'s heat. Drawn in [method _draw],
## no particles. Riders are layered by [member companions] — scenes
## instantiated at [method play] and each handed [member riders]; empty = the
## plain explosive ring. Knobs are tentative defaults, easy to change.

signal finished

## The ring's final radius in world px: the blast's real reach.
@export_range(0.0, 2000.0, 1.0) var radius: float = 120.0:
	set(value):
		radius = maxf(value, 0.0)
		queue_redraw()
## The detonation's power; only [member power_width] reads it.
@export_range(0, 500, 1) var power: int = 0:
	set(value):
		power = maxi(value, 0)
		queue_redraw()
## Seconds from detonation to gone.
@export_range(0.05, 2.0, 0.01) var duration: float = 0.35
## Stroke width in world px before [member power_width].
@export_range(0.5, 24.0, 0.1) var thickness: float = 2.0:
	set(value):
		thickness = value
		queue_redraw()
## Extra stroke px per power unit; 0 = every blast draws one width.
@export_range(0.0, 2.0, 0.01) var power_width: float = 0.0:
	set(value):
		power_width = value
		queue_redraw()
## The glow tier the ring is tinted to ([method Emissive.tint]).
@export var emissive_tier: Emissive.Tier = Emissive.Tier.ALERT:
	set(value):
		emissive_tier = value
		queue_redraw()
## Whose heat the ring carries — the explosive identity.
@export var identity: Identity = null:
	set(value):
		identity = value
		queue_redraw()
## Rider layers, instantiated as children at [method play]; each gets
## [member riders] (and [member radius]) if it declares them.
@export var companions: Array[PackedScene] = []

## The blast's rider identities, explosive stripped ([member BlastMark.riders]).
var riders: Array[Identity] = []

## 0 → 1 across [member duration]; 1 at rest so the editor shows the full ring.
var _t: float = 1.0
var _playing := false
## Set once a sweep ends: a spent ring draws nothing until the next play.
var _spent := false


func _ready() -> void:
	set_process(_playing)


## Set the visual from [param mark] — reach, power, riders.
func setup(mark: BlastMark) -> void:
	radius = mark.reach
	power = mark.power
	riders = mark.riders.duplicate()


## Start the sweep and lay down the companions; [signal finished] at the end.
func play() -> void:
	for scene in companions:
		var companion := scene.instantiate() if scene != null else null
		if companion == null:
			continue
		if &"riders" in companion:
			companion.set(&"riders", riders)
		if &"radius" in companion:
			companion.set(&"radius", radius)
		add_child(companion)
	_t = 0.0
	_playing = true
	_spent = false
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if not _playing:
		return
	_t = minf(_t + delta / maxf(duration, 0.001), 1.0)
	queue_redraw()
	if _t >= 1.0:
		_playing = false
		_spent = true
		set_process(false)
		queue_redraw()
		finished.emit()


func _draw() -> void:
	if radius <= 0.0 or _spent:
		return
	var sweep := 1.0 - pow(1.0 - _t, 3.0)
	var fade := 1.0 if _t < 0.5 else 1.0 - (_t - 0.5) * 2.0
	var base := identity.tint if identity != null else Color.WHITE
	var color := Emissive.tint(base, Emissive.stops(emissive_tier))
	color.a *= clampf(fade, 0.0, 1.0) if _playing else 1.0
	var width := thickness + power_width * float(power)
	draw_arc(Vector2.ZERO, radius * maxf(sweep, 0.02), 0.0, TAU, 96, color, width, true)
