@tool
class_name FrostCrust
extends Node2D
## Ice's Frozen read on the node itself: a crown of frost shards on the rim,
## a shape rather than a tint so it stays distinct from (and composes with)
## the band glow's modulate. Hidden below Frozen; Deep freeze grows it.
## Fed by [method NodeVisualsComposite.set_terrain_glow] through [member level].
## Drawn once per change ([method queue_redraw]), never per frame: one draw
## call per Frozen node, none for the rest.

## 0 hidden, 1 Frozen, 2 Deep freeze.
var level: int = 0:
	set(value):
		level = clampi(value, 0, 2)
		visible = level > 0
		queue_redraw()
## The rim the crust sits on, pushed by the composite.
var radius: float = 32.0:
	set(value):
		radius = value
		queue_redraw()

## The crust's colour (alpha included). Tentative knob; editor feedback: this
## scene, or the composite with a Frozen node in the sandbox.
@export var crust_color := Color(0.85, 0.97, 1.0, 0.85):
	set(value):
		crust_color = value
		queue_redraw()
## Shards around the rim. Tentative.
@export_range(3, 48, 1) var shard_count: int = 14:
	set(value):
		shard_count = value
		queue_redraw()
## A shard's reach past the rim, as a share of [member radius]. Tentative.
@export_range(0.0, 1.0, 0.01) var shard_length: float = 0.22:
	set(value):
		shard_length = value
		queue_redraw()
## Deep freeze's shard reach over Frozen's. Tentative.
@export_range(1.0, 3.0, 0.05) var deep_freeze_scale: float = 1.6:
	set(value):
		deep_freeze_scale = value
		queue_redraw()
## Outline width in px. Tentative.
@export_range(0.5, 6.0, 0.25) var line_width: float = 1.5:
	set(value):
		line_width = value
		queue_redraw()
## The crust's fill alpha, as a share of [member crust_color]'s; the fill
## covers the disc inside the crown (tentative).
@export_range(0.0, 1.0, 0.01) var fill_alpha: float = 0.35:
	set(value):
		fill_alpha = value
		queue_redraw()
## The shortest a shard's random reach gets, as a share of its full reach.
## Tentative.
@export_range(0.0, 1.0, 0.01) var jag_floor: float = 0.55:
	set(value):
		jag_floor = value
		queue_redraw()
## Preview level in the editor (0 shows nothing). Editor-only.
@export_range(0, 2, 1) var editor_preview_level: int = 0:
	set(value):
		editor_preview_level = value
		if Engine.is_editor_hint():
			level = value


func _ready() -> void:
	visible = level > 0


func _draw() -> void:
	if level <= 0 or shard_count < 3:
		return
	var reach := radius * shard_length * (deep_freeze_scale if level >= 2 else 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1807  # a fixed jag, so the crust never shimmers between redraws
	var n := shard_count * 2
	var pts := PackedVector2Array()
	for k in n:
		var a := TAU * float(k) / float(n)
		var r := radius
		if k % 2 == 0:
			r += reach * rng.randf_range(jag_floor, 1.0)
		pts.append(Vector2.from_angle(a) * r)
	var fill := crust_color
	fill.a *= fill_alpha
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, crust_color, line_width, true)
