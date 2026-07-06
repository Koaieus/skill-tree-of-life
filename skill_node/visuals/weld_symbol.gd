@tool
extends SkillNodeVisual
## Weld symbol (#124): a glyph overlay engraved into the same disk gradient
## as inner_disk.gd, not composited on top of it. The fill is NOT a flat
## color under a blend mode — that read as a black sticker whenever the
## disk itself was dark (unallocated). Instead the glyph is filled with a
## per-vertex evaluation of the identical disk shading formula (same
## tint_color/tint_mix/allocated/highlight terms as inner_disk.gdshader),
## so it darkens/lightens exactly like the disk itself. On top, a
## white-then-black hairline pair traces the glyph outline — the classic
## engraved-bevel cue (light line reads as a raised catch-light, the darker
## line right against it reads as the shadowed underside of a groove) via
## plain alpha compositing, no blend mode involved.
##
## Currently a placeholder regular polygon per archetype, swappable later
## (rune/kanji) without touching the shading pipeline.

enum GlowMode { NONE, ALWAYS, HOVER, PULSE, SWEEP }
enum Archetype { STR, DEX, INT, WIS, PER, CON }

## Placeholder glyph = a regular polygon with this many sides per archetype.
const ARCH_SIDES := {
	Archetype.STR: 3,
	Archetype.DEX: 4,
	Archetype.INT: 6,
	Archetype.WIS: 5,
	Archetype.PER: 8,
	Archetype.CON: 12,
}

const NEUTRAL_DARK := Color(0.16, 0.17, 0.20)
const NEUTRAL_LIGHT := Color(0.38, 0.40, 0.45)

## Off by default per the locked design ("showWeld — off is the new default;
## empty center. on restores the archetype shape" — Rim Forge Lab): the disk's
## own semi-sphere shading + specular highlight is the baseline read, the
## glyph is an opt-in accent.
@export var show_weld: bool = false:
	set(value):
		show_weld = value
		queue_redraw()

## Glyph scale relative to the disk radius. At 1.0 the glyph's vertices sit
## exactly on the disk's circle (circumscribed by it).
@export_range(0.4, 1.15, 0.01) var weld_k: float = 0.75:
	set(value):
		weld_k = value
		queue_redraw()

## Reference disk radius the glyph scales against and shades relative to —
## see inner_disk.gd. Kept in sync by [method configure].
@export_range(1.0, 128.0, 0.5) var disk_radius: float = 24.0:
	set(value):
		disk_radius = value
		queue_redraw()

## Same shading inputs as inner_disk.gd — kept identical so the weld reads
## as sunk into the same metal/gem, not a separately-lit sticker.
@export var tint_color: Color = Color(0.291, 0.5892, 1.0):
	set(value):
		tint_color = value
		queue_redraw()
@export_range(0.0, 1.0, 0.01) var tint_mix: float = 0.6:
	set(value):
		tint_mix = value
		queue_redraw()
@export var allocated: bool = false:
	set(value):
		allocated = value
		queue_redraw()
@export var highlight_position: Vector2 = Vector2(-0.35, -0.35):
	set(value):
		highlight_position = value
		queue_redraw()
@export_range(0.0, 1.0, 0.01) var highlight_intensity: float = 0.85:
	set(value):
		highlight_intensity = value
		queue_redraw()

@export var glow_mode: GlowMode = GlowMode.NONE:
	set(value):
		glow_mode = value
		set_process(glow_mode in [GlowMode.HOVER, GlowMode.PULSE, GlowMode.SWEEP])
		queue_redraw()

@export_range(0.0, 1.0, 0.01) var glow_amt: float = 0.4:
	set(value):
		glow_amt = value
		queue_redraw()

## Adds a bloom halo + boosts the glow radius on the allocation glow.
@export var vivid_disk: bool = false:
	set(value):
		vivid_disk = value
		queue_redraw()

@export var arch: Archetype = Archetype.STR:
	set(value):
		arch = value
		queue_redraw()

var _t: float = 0.0


func _ready() -> void:
	set_process(glow_mode in [GlowMode.HOVER, GlowMode.PULSE, GlowMode.SWEEP])


func configure(new_radius: float) -> void:
	super.configure(new_radius)
	disk_radius = new_radius


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _is_hovering() -> bool:
	return get_local_mouse_position().length() <= disk_radius


func _current_glow() -> float:
	match glow_mode:
		GlowMode.NONE:
			return 0.0
		GlowMode.ALWAYS:
			return glow_amt
		GlowMode.HOVER:
			return glow_amt if _is_hovering() else 0.0
		GlowMode.PULSE:
			return glow_amt * (0.5 + 0.5 * sin(_t * 2.5))
		GlowMode.SWEEP:
			return glow_amt
		_:
			return 0.0


## Evaluates the SAME shading formula as inner_disk.gdshader's fragment()
## at one point, in the disk's local (-disk_radius..disk_radius) space —
## the CPU-side, per-vertex twin of that shader, so the two surfaces read
## as one continuous lit material instead of two independently-tinted ones.
func _disk_shade(local_pos: Vector2) -> Color:
	var p := local_pos / disk_radius
	var r2 := p.length_squared()
	var z := sqrt(maxf(0.0, 1.0 - minf(r2, 1.0)))
	var normal := Vector3(p.x, p.y, z).normalized()
	var light_dir := Vector3(highlight_position.x, highlight_position.y, 0.65).normalized()
	var diffuse := maxf(normal.dot(light_dir), 0.0)
	var spec := pow(diffuse, 24.0) * highlight_intensity

	var tinted := Color(0.5, 0.5, 0.5).lerp(tint_color, tint_mix)
	var base_dark := NEUTRAL_DARK.lerp(NEUTRAL_LIGHT, 0.35 + 0.5 * diffuse)
	var base_tint := Color(tinted.r * (0.45 + 0.65 * diffuse), tinted.g * (0.45 + 0.65 * diffuse), tinted.b * (0.45 + 0.65 * diffuse))
	var base := base_tint if allocated else base_dark
	return Color(base.r + spec, base.g + spec, base.b + spec, 1.0)


func _draw() -> void:
	if not show_weld:
		return
	var glyph_r := disk_radius * weld_k
	var sides: int = ARCH_SIDES.get(arch, 6)
	var points := PackedVector2Array()
	for theta in polar_steps(sides):
		points.append(polar_point(glyph_r, theta - PI / 2.0))

	var glow := _current_glow()
	if vivid_disk:
		glow *= 1.6
	if glow > 0.0:
		var halo_scale := 1.0 + (0.5 if vivid_disk else 0.25)
		var halo_points := PackedVector2Array()
		for p in points:
			halo_points.append(p * halo_scale)
		draw_colored_polygon(halo_points, Color(1.0, 1.0, 1.0, glow * 0.35))

	if glow_mode == GlowMode.SWEEP and glow > 0.0:
		var sweep_theta := fmod(_t * 1.5, TAU)
		draw_line(Vector2.ZERO, polar_point(glyph_r * 1.4, sweep_theta), Color(1.0, 1.0, 1.0, glow * 0.6), 2.0, true)

	var colors := PackedColorArray()
	for p in points:
		colors.append(_disk_shade(p))
	draw_polygon(points, colors)

	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color(1.0, 1.0, 1.0, 0.32), 0.9, true)
	draw_polyline(outline, Color(0.0, 0.0, 0.0, 0.28), 0.5, true)
