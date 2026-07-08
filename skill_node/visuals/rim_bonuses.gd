@tool
extends SkillNodeRingVisual
## Rim bonuses (#127): two independent composable layers on/around the
## structural rim — rimTone (archetype-tinted, dims like the disk when
## unallocated) and rimHolder (always neutral chrome, ignores tint/
## allocation — the "stable basket" pinning things down) — plus the
## stake-fill dial (#127 follow-up): a current/max glow ring drawn over a
## dark backdrop across this ring's own [inner_radius, outer_radius] band
## (see [SkillNodeRingVisual]), independent of rim_tone/rim_holder.

enum RimTone { NONE, GROOVE, OVERLAY }
enum RimHolder { NONE, BRACES, FILIGREE }
enum HolderAlign { STAGGERED, JOINED }

const MARK_COUNT := 8
const NEUTRAL_CHROME := Color(0.72, 0.74, 0.78)
const GROOVE_COLOR := Color(0.05, 0.05, 0.07, 0.85)
## Arc resolution: draw_arc points per full TAU sweep, scaled by span.
const FULL_CIRCLE_SEGMENTS := 64

## Archetype-tinted tone color for RimTone.OVERLAY gems, direct from the
## composing SkillNode (mirrors rune_ring.gd's tint_color — no lossy
## hue-only round trip). Dims to neutral grey when unallocated, same as
## the inner disk.
@export var tone_tint: Color = Color(0.5, 0.5, 0.55):
	set(value):
		tone_tint = value
		queue_redraw()

## Dims to a neutral grey when false — same dims-when-unallocated behavior
## as the inner disk (rimTone is archetype-tinted, not rimHolder).
@export var allocated: bool = false:
	set(value):
		allocated = value
		queue_redraw()

@export var rim_tone: RimTone = RimTone.NONE:
	set(value):
		rim_tone = value
		queue_redraw()
@export var rim_holder: RimHolder = RimHolder.NONE:
	set(value):
		rim_holder = value
		queue_redraw()
## staggered = holder marks sit BETWEEN the tone gems; joined = holder marks
## sit directly on top of them.
@export var rim_holder_align: HolderAlign = HolderAlign.STAGGERED:
	set(value):
		rim_holder_align = value
		queue_redraw()

## Gem size as a fraction of the rim width (outer_radius - inner_radius) —
## scales with node size instead of a fixed px value.
@export_range(0.1, 1.0, 0.01) var gem_size_fraction: float = 0.5:
	set(value):
		gem_size_fraction = value
		queue_redraw()

## --- Stake-fill dial ---------------------------------------------------
## Current fill count (M). 0 -> draw nothing. Synced by the composing
## SkillNode to its allocation_level.
@export_range(0, 8, 1) var fill_current: int = 0:
	set(value):
		fill_current = value
		set_process(fill_current > 0)
		queue_redraw()
## Max slots (N). Synced by the composing SkillNode to its stake_level.
## fill_max == 1 is the special "single glowing ring" case (no segments).
@export_range(1, 8, 1) var fill_max: int = 1:
	set(value):
		fill_max = maxi(value, 1)
		queue_redraw()
## Glow tint — the allocating entity's color, matching the lit-edge glow
## (see graph/edge.gd's `is_lit` treatment). Synced by the composing
## SkillNode to entity_tint.
@export var fill_glow_tint: Color = Color(0.291, 0.5892, 1.0):
	set(value):
		fill_glow_tint = value
		queue_redraw()
## Angular gap between adjacent fill slots, in degrees. Applies uniformly
## across all N slots (filled or not), so partially-filled dials still read
## as evenly spaced segments.
@export_range(0.0, 60.0, 0.5) var fill_gap_deg: float = 10.0:
	set(value):
		fill_gap_deg = value
		queue_redraw()
## How fast the filled arcs spin around the groove, radians/sec.
@export_range(0.0, 2.0, 0.01) var fill_spin_speed: float = 0.2

var _t: float = 0.0


func _tone_color() -> Color:
	if not allocated:
		return Color(0.5, 0.5, 0.55)
	return tone_tint


func _ready() -> void:
	set_process(fill_current > 0)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var rim_width := outer_radius - inner_radius
	if rim_width <= 0.0:
		return
	match rim_tone:
		RimTone.GROOVE:
			draw_circle(Vector2.ZERO, inner_radius, GROOVE_COLOR, false, 2.0, true)
		RimTone.OVERLAY:
			_draw_marks(polar_steps(MARK_COUNT), rim_width, gem_size_fraction, _tone_color(), true)
		RimTone.NONE:
			pass

	_draw_stake_fill(rim_width)

	if rim_holder == RimHolder.NONE:
		return
	var holder_angles := polar_steps(MARK_COUNT)
	if rim_holder_align == HolderAlign.STAGGERED and MARK_COUNT > 0:
		var half_step := PI / float(MARK_COUNT)
		var offset := PackedFloat32Array()
		for a in holder_angles:
			offset.append(a + half_step)
		holder_angles = offset
	match rim_holder:
		RimHolder.BRACES:
			_draw_marks(holder_angles, rim_width, gem_size_fraction * 0.6, NEUTRAL_CHROME, false)
		RimHolder.FILIGREE:
			_draw_filigree(holder_angles, rim_width)
		RimHolder.NONE:
			pass


func _draw_marks(angles: PackedFloat32Array, rim_width: float, size_fraction: float, color: Color, diamond: bool) -> void:
	var r := (inner_radius + outer_radius) * 0.5
	var half := rim_width * size_fraction * 0.5
	for theta in angles:
		var center := polar_point(r, theta)
		var radial := Vector2(cos(theta), sin(theta))
		var tangent := Vector2(-sin(theta), cos(theta))
		var points: PackedVector2Array
		if diamond:
			points = PackedVector2Array([
				center + radial * half, center + tangent * half,
				center - radial * half, center - tangent * half,
			])
		else:
			points = PackedVector2Array([
				center + radial * half + tangent * half,
				center + radial * half - tangent * half,
				center - radial * half - tangent * half,
				center - radial * half + tangent * half,
			])
		draw_colored_polygon(points, color)


## Wire-scrollwork placeholder: a small stroked loop per holder mark.
func _draw_filigree(angles: PackedFloat32Array, rim_width: float) -> void:
	var r := (inner_radius + outer_radius) * 0.5
	var loop_r := rim_width * 0.28
	for theta in angles:
		var center := polar_point(r, theta)
		draw_arc(center, loop_r, 0.0, TAU, 10, NEUTRAL_CHROME, 1.2, true)


## current/max glow dial, drawn over a dark backdrop across the ring band:
##   0/*  -> nothing (not even the backdrop)
##   1/1  -> one full glowing ring, no segments
##   M/N  -> N evenly-gapped slots around the circle, the first M lit,
##           slowly spinning together along the groove
func _draw_stake_fill(rim_width: float) -> void:
	if fill_current <= 0:
		return
	var r := (inner_radius + outer_radius) * 0.5
	draw_circle(Vector2.ZERO, r, GROOVE_COLOR, false, rim_width, true)

	if fill_max <= 1:
		_draw_glow_arc(r, rim_width, 0.0, TAU)
		return

	var gap_rad := deg_to_rad(fill_gap_deg)
	var slot_width := maxf((TAU - fill_max * gap_rad) / float(fill_max), 0.0)
	var filled := mini(fill_current, fill_max)
	var spin := _t * fill_spin_speed
	for i in filled:
		var start := spin + i * (slot_width + gap_rad)
		_draw_glow_arc(r, rim_width, start, start + slot_width)


## Fakes glow via stacked translucent strokes (same CPU technique as
## core_halos.gd/rune_ring.gd's edge_glow) rather than a shader — no
## project-wide glow/bloom environment exists yet to justify one.
func _draw_glow_arc(r: float, rim_width: float, start: float, end: float) -> void:
	var span := end - start
	if span <= 0.0:
		return
	var points: int = maxi(int(FULL_CIRCLE_SEGMENTS * span / TAU), 4)
	var halo := Color(fill_glow_tint.r, fill_glow_tint.g, fill_glow_tint.b, 0.22)
	var mid := Color(fill_glow_tint.r, fill_glow_tint.g, fill_glow_tint.b, 0.5)
	var core := fill_glow_tint.lightened(0.35)
	core.a = 0.95
	draw_arc(Vector2.ZERO, r, start, end, points, halo, rim_width * 1.8, true)
	draw_arc(Vector2.ZERO, r, start, end, points, mid, rim_width * 1.1, true)
	draw_arc(Vector2.ZERO, r, start, end, points, core, rim_width * 0.55, true)
