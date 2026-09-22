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
## The segment sweep, shared with [PoolGauge]. See [GaugeSpark].
var _spark := GaugeSpark.new(self, _push)
## Set while [method set_buckets] is writing its four properties one at a time;
## the intermediate states are not events, so only the last write sweeps.
var _batching: bool = false

## The bucket shares the shader is drawing right now — `(to_spend, wounded,
## staked)` over the pool max — lagging the model while a run's boundary sweeps
## one cell per [member cell_step_time] (#882). [GaugeSpark] tweens it.
var shown_fractions: Vector3 = Vector3.ZERO:
	set(v):
		shown_fractions = v
		_push(&"fractions", v)

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
@export_range(0.0, 3.0, 0.05) var glow_stops: float = 2.0:
	set(v):
		glow_stops = v
		_push(&"glow_stops", v)

## The tier a cell burns at the instant it changes bucket — see
## [member PoolGauge.spark_stops].
@export_range(0.0, 3.0, 0.05) var spark_stops: float = 2.5:
	set(v):
		spark_stops = v
		_push(&"spark_stops", v)

## How long the crossing cell takes to cool back to [member glow_stops] once a
## sweep lands.
@export_range(0.05, 2.0, 0.01) var spark_time: float = 0.45

## Seconds a run's boundary spends crossing ONE cell — see
## [member PoolGauge.cell_step_time]; same knob, same pacing.
@export_range(0.02, 1.0, 0.01) var cell_step_time: float = 0.25

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

@export var subdivisions: int = 0:
	set(v):
		subdivisions = v
		_resolve_cells()


func _resolve_cells() -> void:
	pass


## 0 = smooth continuous bar. N = N skewed parallelogram cells (mirrors
## PoolGauge; usually bound to the pool's max, same as AP/DP/Move).
@export_range(0.0, 24.0, 1.0) var cell_count: float = 0.0:
	set(v):
		var old := cell_count
		cell_count = v
		_push(&"cell_count", v)
		# The strip just re-scaled (the SP cap moved). That is not points
		# changing hands, so keep the displayed boundaries on the CELLS they
		# were on rather than on their old shares of a strip that no longer
		# exists — a level-up would otherwise sweep every run at once. Bind
		# cell_count BEFORE the buckets so the gain that came with the new cap
		# still gets its own sweep.
		if old > 0.0 and v > 0.0 and not is_equal_approx(old, v):
			_spark.snap(self, ^"shown_fractions", shown_fractions * (old / v))

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
	shown_fractions = _target_fractions()
	_push(&"color_0", color_to_spend)
	_push(&"color_1", color_wounded)
	_push(&"color_2", color_staked)
	_push(&"color_background", color_allocated)
	_push(&"glow_color", glow_color)
	_push(&"glow_stops", glow_stops)
	_push(&"spark_stops", spark_stops)
	_spark.push_initial()
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
	_batching = true
	to_spend = p_to_spend
	wounded = p_wounded
	staked = p_staked
	max_value = p_max_value
	_batching = false
	_push_fractions()


## Open a window in which bucket writes land with no ignition — the paint a bind
## or a hot-seat rebind does. Pair with [method end_snap]; see
## [member GaugeSpark.snapping].
func begin_snap() -> void:
	_spark.snapping = true


func end_snap() -> void:
	_spark.snapping = false


## The model's bucket shares, `(to_spend, wounded, staked)` over the pool max —
## what [member shown_fractions] sweeps toward.
func _target_fractions() -> Vector3:
	var denom := maxf(max_value, to_spend + wounded + staked)
	if denom <= 0.0:
		return Vector3.ZERO
	return Vector3(to_spend / denom, wounded / denom, staked / denom)


## Where each run boundary falls for a given set of shares, in strip cells:
## `[to_spend | allocated | wounded | staked]`, so the runs are `[0, b0)`,
## `[b0, b1)`, `[b1, b2)`, `[b2, b3)` — the same arithmetic as the shader's.
func _bounds_of(f: Vector3) -> PackedFloat32Array:
	var n := cell_count
	return PackedFloat32Array([f.x * n, (1.0 - f.y - f.z) * n, (1.0 - f.z) * n, n])


## Sweep the display to the model. The boundary that moved furthest is the one
## that changed a run's membership and the one whose crossing cell burns —
## `spark_edge` names it for the shader (0..3, the `_bounds_of` order). A
## spend shifts `b0` alone and a wound `b1` alone; a heal, stake or extract is
## a TRANSFER between the to-spend run and a trailing one, so two boundaries
## move the same distance at once — both sweep together (one tween carries all
## three shares), and on the tie the trailing run's edge takes the lift, since
## the wound or the stake is the story, not the point coming home. b3 never
## moves. The duration is that boundary's distance in cells, one step per cell.
##
## A boundary moving LEFT grows the run on its right (a wound grows the wounded
## run leftward out of the allocated headroom) — so the trailing runs originate
## from the right and the to-spend run from the left, with no anchor to choose:
## the geometry falls out of which way the boundary travels.
func _push_fractions() -> void:
	if _batching:
		return
	var target := _target_fractions()
	var was := _bounds_of(shown_fractions)
	var now := _bounds_of(target)
	var cells := 0.0
	var edge := 0
	for i in 4:
		var d := now[i] - was[i]
		if absf(d) >= absf(cells) - 0.001 and absf(d) > 0.001:
			cells = d
			edge = i
	# Signed for the shader's sake: the to-spend run sits LEFT of `b0` and
	# shrinks when it moves left, the trailing runs sit RIGHT of their boundary
	# and shrink when it moves right.
	var leaving := cells < 0.0 if edge == 0 else cells > 0.0
	_spark.sweep(self, ^"shown_fractions", target, -absf(cells) if leaving else absf(cells),
			cell_step_time, spark_time, float(edge))

func _push(param: StringName, value: Variant) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(param, value)
