@tool
class_name ShredderVisual
extends AddonVisual

## Shredder's drawing: a cracked iron plate shedding spark shards. The carrier
## wears an outboard band of [member plate_segments] iron plates split by
## jagged cracks; each crack flickers hot, and [member shard_count] spark
## shards break off the cracks and fly OUTWARD, cooling from a hot spark to the
## identity tint as they go — Sunder's arrow look (armor flaking off the hit)
## on a standing node. One [method _draw] pass for all of it, never a node per
## shard. Colour is the parent addon's identity tint; the iron is a dark grey,
## the sparks glow on a named [enum Emissive.Tier].
##
## Animation is a pure function of time and a per-carrier seed, redrawn at
## [member redraw_hz] and only while visible (a board draws a few hundred
## carriers; the cost is CPU draw-list rebuilds).

const _FALLBACK_TINT := Color(0.7, 0.3, 0.22)
## The plate's iron, darkened toward the tint at its cracked edges.
const _IRON := Color(0.32, 0.33, 0.36)
## A fresh spark's colour before it cools to the tint.
const _SPARK := Color(1.0, 0.78, 0.4)

## Iron plates the band is split into (a crack between each pair).
@export_range(3, 16, 1) var plate_segments: int = 6:
	set(value):
		plate_segments = value
		queue_redraw()
## The band's width, as a fraction of the carrier's radius.
@export_range(0.04, 0.4, 0.01) var plate_width: float = 0.16:
	set(value):
		plate_width = value
		queue_redraw()
## Width of the gap a crack opens between two plates, in radians.
@export_range(0.02, 0.5, 0.01) var crack_gap: float = 0.14:
	set(value):
		crack_gap = value
		queue_redraw()
## Spark shards alive at once on one carrier — the hard per-node cap.
@export_range(1, 24, 1) var shard_count: int = 8:
	set(value):
		shard_count = value
		queue_redraw()
## A shard's length, as a fraction of the carrier's radius.
@export_range(0.02, 0.3, 0.01) var shard_size: float = 0.09:
	set(value):
		shard_size = value
		queue_redraw()
## Shard lives per second (one life = break off, fly out, cool).
@export_range(0.05, 3.0, 0.05) var shard_speed: float = 0.6:
	set(value):
		shard_speed = value
		queue_redraw()
## How far past the band a shard flies, x the carrier's radius.
@export_range(0.0, 2.0, 0.05) var shard_distance: float = 0.6:
	set(value):
		shard_distance = value
		queue_redraw()
## Glow tier of the cracks and sparks (`.claude/rules/hdr-color.md`); the iron
## itself stays a plain colour.
@export var spark_tier: Emissive.Tier = Emissive.Tier.LABEL:
	set(value):
		spark_tier = value
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


## Stable per-carrier offset so neighbouring carriers never spark in step.
func _seed() -> float:
	return _hash(global_position.x * 0.173 + global_position.y * 0.293)


static func _hash(x: float) -> float:
	return fposmod(sin(x * 12.9898) * 43758.5453, 1.0)


func _draw() -> void:
	if radius <= 0.0:
		return
	var tint := _tint()
	var hot := Emissive.at(_SPARK.lerp(tint, 0.3), Emissive.stops(spark_tier))
	var seed := _seed()
	_draw_plates(tint, hot, seed)
	_draw_shards(tint, hot, seed)


## The angle of crack [param i], jittered per carrier so plates differ in size.
func _crack_angle(i: int, seed: float) -> float:
	var span := TAU / float(plate_segments)
	return span * (float(i) + 0.3 * (_hash(float(i) * 5.7 + seed * 31.0) - 0.5))


## The band: iron plates between the cracks, each crack a jagged hot seam.
func _draw_plates(tint: Color, hot: Color, seed: float) -> void:
	var inner := radius * 1.06
	var outer := inner + radius * plate_width
	var iron := _IRON.lerp(tint, 0.25)
	for i in plate_segments:
		var a0 := _crack_angle(i, seed) + crack_gap * 0.5
		var a1 := _crack_angle(i + 1, seed) - crack_gap * 0.5
		if i + 1 == plate_segments:
			a1 = _crack_angle(0, seed) + TAU - crack_gap * 0.5
		if a1 <= a0:
			continue
		var steps := maxi(3, int((a1 - a0) / 0.2))
		var poly := PackedVector2Array()
		for s in steps + 1:
			poly.append(Vector2.from_angle(lerpf(a0, a1, float(s) / float(steps))) * outer)
		for s in steps + 1:
			poly.append(Vector2.from_angle(lerpf(a1, a0, float(s) / float(steps))) * inner)
		draw_colored_polygon(poly, Color(iron, 0.9))
		# A rivet mid-plate sells it as armour, not a ring.
		draw_circle(Vector2.from_angle((a0 + a1) * 0.5) * (inner + outer) * 0.5,
				radius * plate_width * 0.16, Color(tint, 0.9))
	# The cracks: a zig-zag seam across the band, flickering hot.
	var width := maxf(1.0, radius * 0.03)
	for i in plate_segments:
		var a := _crack_angle(i, seed)
		var h := _hash(float(i) * 2.3 + seed * 17.0)
		var flicker := 0.55 + 0.45 * sin((_time * 3.0 + h) * TAU)
		var jag := crack_gap * 0.35
		var seam := PackedVector2Array([
			Vector2.from_angle(a) * inner,
			Vector2.from_angle(a + jag) * lerpf(inner, outer, 0.35),
			Vector2.from_angle(a - jag) * lerpf(inner, outer, 0.7),
			Vector2.from_angle(a) * outer,
		])
		draw_polyline(seam, Color(hot, flicker), width)


## The shards: break off a crack, fly outward and spin, cooling and fading.
func _draw_shards(tint: Color, hot: Color, seed: float) -> void:
	if shard_count <= 0:
		return
	var from_r := radius * (1.06 + plate_width)
	var size := radius * shard_size
	for i in shard_count:
		var h := _hash(float(i) + seed * 97.0)
		var crack := int(h * float(plate_segments)) % plate_segments
		var theta := _crack_angle(crack, seed) + (h - 0.5) * crack_gap
		var life := fposmod(_time * shard_speed * (0.8 + 0.4 * h) + h, 1.0)
		var dir := Vector2.from_angle(theta)
		var center := dir * (from_r + life * shard_distance * radius)
		var colour := hot.lerp(tint, life)
		var s := size * (1.0 - 0.5 * life)
		# A sliver tumbling outward: a thin triangle along its spin.
		var spin := theta + (life * 2.5 + h) * TAU
		var along := Vector2.from_angle(spin) * s
		var across := Vector2.from_angle(spin + PI * 0.5) * s * 0.3
		draw_colored_polygon(PackedVector2Array([center + along, center + across,
				center - along]), Color(colour, 0.9 * (1.0 - life)))
