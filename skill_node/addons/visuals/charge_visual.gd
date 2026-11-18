@tool
class_name ChargeVisual
extends AddonVisual

## The Charge addon's drawing: [member spark_count] jagged sparks crackling
## around the carrier's rim, re-rolled [member flicker_hz] times a second, one
## [method _draw] pass for all of them. Colour is the parent addon's identity
## tint (Lightning's); the sparks glow on a named [enum Emissive.Tier].

const _FALLBACK_TINT := Color(0.55, 0.55, 1.0)

## Sparks on one carrier at once.
@export_range(1, 12, 1) var spark_count: int = 4:
	set(value):
		spark_count = value
		queue_redraw()
## A spark's length, × the carrier's radius.
@export_range(0.1, 1.5, 0.05) var spark_length: float = 0.6:
	set(value):
		spark_length = value
		queue_redraw()
## Kinks per spark.
@export_range(1, 6, 1) var kinks: int = 3:
	set(value):
		kinks = value
		queue_redraw()
## How often the sparks re-roll, in Hz (the crackle; also the redraw cap).
@export_range(2.0, 30.0, 1.0) var flicker_hz: float = 10.0
## Glow tier of the sparks (`.claude/rules/hdr-color.md`).
@export var spark_tier: Emissive.Tier = Emissive.Tier.LABEL:
	set(value):
		spark_tier = value
		queue_redraw()

var _frame := 0
var _since := 0.0


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_since += delta
	if _since >= 1.0 / flicker_hz:
		_since = 0.0
		_frame += 1
		queue_redraw()


func _tint() -> Color:
	var addon := get_parent() as SkillNodeAddon
	if addon != null and addon.tint.a > 0.0:
		return addon.tint
	return _FALLBACK_TINT


func _draw() -> void:
	if radius <= 0.0 or spark_count <= 0:
		return
	var glow := Emissive.at(_tint(), Emissive.stops(spark_tier))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(int(global_position.x), int(global_position.y), _frame))
	for i in spark_count:
		var theta := TAU * (float(i) + rng.randf()) / float(spark_count)
		var radial := Vector2.from_angle(theta)
		var side := radial.orthogonal()
		var points := PackedVector2Array([radial * radius])
		for k in kinks:
			var f := float(k + 1) / float(kinks + 1)
			var jitter := (rng.randf() - 0.5) * radius * spark_length * 0.5
			points.append(radial * radius * (1.0 + spark_length * f) + side * jitter)
		points.append(radial * radius * (1.0 + spark_length))
		draw_polyline(points, glow, maxf(1.0, radius * 0.05))
