@tool
extends SkillNodeVisual
## Weld symbol (#124): a glyph overlay composited on top of the inner disk
## via CanvasItem material blending. Styling/blend mode are locked in per
## the design doc; only the glyph geometry is still open — currently a
## placeholder regular polygon per archetype, swappable later (rune/kanji)
## without touching the blend pipeline.

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

@export var show_weld: bool = true:
	set(value):
		show_weld = value
		queue_redraw()

## Glyph scale relative to the disk radius rC.
@export_range(0.4, 1.15, 0.01) var weld_k: float = 0.75:
	set(value):
		weld_k = value
		queue_redraw()

## Reference disk radius (rC) the glyph scales against — see inner_disk.gd.
@export var disk_radius: float = 24.0:
	set(value):
		disk_radius = value
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

var _material: CanvasItemMaterial
var _t: float = 0.0


func _ready() -> void:
	# resource_local_to_scene — one material per node instance; see
	# .claude/rules/godot-workflow.md.
	_material = CanvasItemMaterial.new()
	_material.resource_local_to_scene = true
	_material.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	material = _material
	set_process(glow_mode in [GlowMode.HOVER, GlowMode.PULSE, GlowMode.SWEEP])


func configure(new_radius: float) -> void:
	super.configure(new_radius)


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

	draw_colored_polygon(points, Color(1, 1, 1, 1))
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color(0, 0, 0, 0.6), 1.5, true)
