@tool
class_name CompositeBarGauge
extends ColorRect
## Proportional multi-bucket bar — the Skill Points composition bar.
## Distinct contract from PoolGauge: three independent buckets (to_spend/
## wounded/staked) against a pool max instead of one current/max. Draw order
## is to-spend, allocated, wounded, staked — allocated is the remainder
## (max_value - the other three) rendered as plain background rather than a
## fourth colored bucket, and wounds/staked deliberately trail at the end so
## the "available" segment reads first (and glows — see glow_color).
## Bucket 1 in draw order ("wounded") pulses per the design's woundPulse
## keyframe.
##
## `cell_count == 0` renders a smooth bar; `cell_count > 0` renders N skewed
## parallelogram "battery" cells, mirroring PoolGauge's shine/cell/skew
## uniform-naming convention.

## Which bucket a screen position falls in — same left-to-right draw order
## as the shader (to-spend, allocated, wounded, staked). Emitted by hover.
enum Bucket { TO_SPEND, ALLOCATED, WOUNDED, STAKED }

## Fires as the mouse moves over a new segment (bucket changes, not every
## pixel). Callers typically light up a matching legend entry — see
## turn_resources_panel.gd for the pattern.
signal segment_hovered(bucket: Bucket)
signal segment_unhovered

var _hovered_bucket: int = -1

@export var to_spend: float = 1.0:
	set(v):
		to_spend = v
		_push_fractions()

@export var wounded: float = 2.0:
	set(v):
		wounded = v
		_push_fractions()

@export var staked: float = 1.0:
	set(v):
		staked = v
		_push_fractions()

## The skill point pool's max (== SkillPointStat.value). Denominator for all
## three bucket fractions; whatever isn't covered by to_spend/wounded/staked
## renders as empty background, not a filled segment.
@export var max_value: float = 10.0:
	set(v):
		max_value = v
		_push_fractions()

@export var color_to_spend: Color = Color(0.2606, 0.6387, 0.9922, 1.0):
	set(v):
		color_to_spend = v
		_push(&"color_0", v)

@export var color_wounded: Color = Color(0.8725, 0.2322, 0.2404, 1.0):
	set(v):
		color_wounded = v
		_push(&"color_1", v)

@export var color_staked: Color = Color(0.9084, 0.6684, 0.3042, 1.0):
	set(v):
		color_staked = v
		_push(&"color_2", v)

## The "allocated" (headroom already spent into owned nodes) segment —
## rendered as plain background, not a colored bucket, but still exposed
## here so legend swatches / hover tooltips share the same color source as
## the gauge instead of duplicating the shader's default.
@export var color_allocated: Color = Color(0.588, 0.647, 0.784, 0.30):
	set(v):
		color_allocated = v
		_push(&"color_background", v)

## Glow tint for the to-spend segment's shine sweep (the "available" bucket
## is meant to read as the most eye-catching one — glowy, always drawn first).
@export var glow_color: Color = Color(0.2606, 0.6387, 0.9922, 0.6):
	set(v):
		glow_color = v
		_push(&"glow_color", v)

## EV stops the to-spend shine trace is lifted by — see [member PoolGauge.glow_stops];
## same knob, same peak-channel normalization, same bloom dependency.
@export_range(0.0, 3.0, 0.05) var glow_stops: float = 2.5:
	set(v):
		glow_stops = v
		_push(&"glow_stops", v)

@export_range(0.0, 20.0, 0.5) var corner_radius: float = 5.0:
	set(v):
		corner_radius = v
		_push(&"corner_radius", v)

@export_range(0.0, 8.0, 0.05) var pulse_speed: float = 2.4:
	set(v):
		pulse_speed = v
		_push(&"pulse_speed", v)

@export_range(0.0, 4.0, 0.05) var shine_speed: float = 0.6:
	set(v):
		shine_speed = v
		_push(&"shine_speed", v)

## 0 = smooth continuous bar. N = N skewed parallelogram cells (mirrors
## PoolGauge; usually bound to the pool's max, same as AP/DP/Move).
@export_range(0.0, 24.0, 1.0) var cell_count: float = 0.0:
	set(v):
		cell_count = v
		_push(&"cell_count", v)

@export_range(-45.0, 45.0, 0.5) var skew_degrees: float = -15.0:
	set(v):
		skew_degrees = v
		_push(&"skew_degrees", v)

@export_range(0.0, 12.0, 0.5) var cell_gap: float = 3.0:
	set(v):
		cell_gap = v
		_push(&"cell_gap", v)

func _ready() -> void:
	if material == null:
		material = preload("res://ui/gauges/composite_bar_gauge_material.tres").duplicate()
	resized.connect(_push_size)
	_push_size()
	_push_fractions()
	_push(&"color_0", color_to_spend)
	_push(&"color_1", color_wounded)
	_push(&"color_2", color_staked)
	_push(&"color_background", color_allocated)
	_push(&"glow_color", glow_color)
	_push(&"glow_stops", glow_stops)
	_push(&"corner_radius", corner_radius)
	_push(&"pulse_speed", pulse_speed)
	_push(&"shine_speed", shine_speed)
	_push(&"cell_count", cell_count)
	_push(&"skew_degrees", skew_degrees)
	_push(&"cell_gap", cell_gap)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(_on_mouse_exited)


## Hover detection ignores the shader's per-cell skew (a cosmetic lean) and
## just maps x/width against the same cumulative bucket boundaries the
## shader colors by — plenty precise for a cursor affordance.
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion) or size.x <= 0.0:
		return
	var u: float = clampf(event.position.x / size.x, 0.0, 1.0)
	var bucket := _bucket_at(u)
	if bucket == _hovered_bucket:
		return
	_hovered_bucket = bucket
	segment_hovered.emit(bucket)


func _on_mouse_exited() -> void:
	_hovered_bucket = -1
	segment_unhovered.emit()


func _bucket_at(u: float) -> int:
	var denom := maxf(max_value, to_spend + wounded + staked)
	if denom <= 0.0:
		return Bucket.ALLOCATED
	var b0 := to_spend / denom
	var b1 := b0 + maxf(0.0, 1.0 - (to_spend + wounded + staked) / denom)
	var b2 := b1 + wounded / denom
	if u < b0:
		return Bucket.TO_SPEND
	if u < b1:
		return Bucket.ALLOCATED
	if u < b2:
		return Bucket.WOUNDED
	return Bucket.STAKED

func _push_size() -> void:
	_push(&"size", size)

## Sets all three buckets + the pool max in one call (the usual binding path
## from a SkillPointStat) rather than firing four separate setters.
func set_buckets(p_to_spend: float, p_wounded: float, p_staked: float, p_max_value: float) -> void:
	to_spend = p_to_spend
	wounded = p_wounded
	staked = p_staked
	max_value = p_max_value

func _push_fractions() -> void:
	var denom := maxf(max_value, to_spend + wounded + staked)
	if denom <= 0.0:
		_push(&"fractions", Vector3(0.0, 0.0, 0.0))
		return
	_push(&"fractions", Vector3(to_spend / denom, wounded / denom, staked / denom))

func _push(param: StringName, value: Variant) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(param, value)
