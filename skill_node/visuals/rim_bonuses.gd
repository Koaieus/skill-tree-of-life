@tool
extends SkillNodeRingVisual
## Rim bonuses (#127): two independent composable layers on/around the
## structural rim — rimTone (archetype-tinted, dims like the disk when
## unallocated) and rimHolder (always neutral chrome, ignores tint/
## allocation — the "stable basket" pinning things down).

enum RimTone { NONE, GROOVE, OVERLAY }
enum RimHolder { NONE, BRACES, FILIGREE }
enum HolderAlign { STAGGERED, JOINED }

const MARK_COUNT := 8
const NEUTRAL_CHROME := Color(0.72, 0.74, 0.78)
const GROOVE_COLOR := Color(0.05, 0.05, 0.07, 0.85)

@export var geom_crest_r: float = 28.0:
	set(value):
		geom_crest_r = value
		queue_redraw()
@export var geom_rim_r: float = 32.0:
	set(value):
		geom_rim_r = value
		queue_redraw()

@export_range(0.0, 360.0, 1.0) var hue: float = 220.0:
	set(value):
		hue = value
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

## Gem size as a fraction of the rim width (rimR - crestR) — scales with
## node size instead of a fixed px value.
@export_range(0.1, 1.0, 0.01) var gem_size_fraction: float = 0.5:
	set(value):
		gem_size_fraction = value
		queue_redraw()


func _tone_color() -> Color:
	if not allocated:
		return Color(0.5, 0.5, 0.55)
	return Color.from_hsv(hue / 360.0, 0.65, 0.9)


func _draw() -> void:
	var rim_width := geom_rim_r - geom_crest_r
	if rim_width <= 0.0:
		return
	match rim_tone:
		RimTone.GROOVE:
			draw_circle(Vector2.ZERO, geom_crest_r, GROOVE_COLOR, false, 2.0, true)
		RimTone.OVERLAY:
			_draw_marks(polar_steps(MARK_COUNT), rim_width, gem_size_fraction, _tone_color(), true)
		RimTone.NONE:
			pass

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
	var r := (geom_crest_r + geom_rim_r) * 0.5
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
	var r := (geom_crest_r + geom_rim_r) * 0.5
	var loop_r := rim_width * 0.28
	for theta in angles:
		var center := polar_point(r, theta)
		draw_arc(center, loop_r, 0.0, TAU, 10, NEUTRAL_CHROME, 1.2, true)
