@tool
class_name CoreSigilBloom
extends SkillNodeVisual
## The core-presence BLOOM (emblem Register 3): the owner core-class [Sigil]
## rendered as an additive, entity-tinted glow that says "this node is the
## entity's core, right here." A separate register from the central carve, so
## it layers OVER whatever the carve resolver draws — a core node that also
## grants a spell shows the spell carve haloed by this glow, no conflict.
##
## LOD split (#167): the on-graph node draws this glowing silhouette; the hero
## card draws the full shaded sigil. Same sigil, two fidelities — never absent.
##
## Reads [member SkillNodeVisual.entity_tint] (ownership — "this is YOUR core").
## Additive blend comes from a shared [CanvasItemMaterial]; the base class's
## `_validate_property` keeps `material` out of the saved scene, so assigning it
## in code never bakes a per-instance material.

## Shared additive-blend material — one object for every bloom (it carries no
## per-instance state), mirroring the family's shared-material convention.
static var _add_material: CanvasItemMaterial

## The mark to bloom. Null → nothing drawn (an unowned or non-core node).
@export var sigil: Sigil = null:
	set(value):
		sigil = value
		set_animating(sigil != null and pulse_depth > 0.0)
		queue_redraw()

## Sigil size as a fraction of the node radius.
@export_range(0.1, 1.5, 0.01) var sigil_scale: float = 0.6:
	set(value):
		sigil_scale = value
		queue_redraw()

## Additive glow passes stacked outward from the mark, and how far they spread.
@export_range(1, 8, 1) var glow_layers: int = 5:
	set(value):
		glow_layers = value
		queue_redraw()

@export_range(0.0, 6.0, 0.1) var glow_spread: float = 2.6:
	set(value):
		glow_spread = value
		queue_redraw()

## How white-hot the mark's core reads (0 = pure entity tint, 1 = white).
@export_range(0.0, 1.0, 0.01) var core_whiteness: float = 0.7:
	set(value):
		core_whiteness = value
		queue_redraw()

## Pulse depth (0 = steady beacon) and rate.
@export_range(0.0, 0.5, 0.01) var pulse_depth: float = 0.12:
	set(value):
		pulse_depth = value
		set_animating(sigil != null and pulse_depth > 0.0)
		queue_redraw()

@export_range(0.05, 4.0, 0.05) var pulse_speed: float = 0.9


func _ready() -> void:
	if material == null:
		material = _shared_add_material()


func _draw() -> void:
	if sigil == null:
		return
	var pts := sigil.points(radius * sigil_scale)
	if pts.size() < 2:
		return
	var pulse := 1.0 + pulse_depth * sin(anim_time * pulse_speed * TAU)

	# Outer glow: entity-tinted, stacked outward at falling alpha. Additive
	# summation of the passes reads as a soft bloom around the mark.
	var glow := entity_tint
	for i in glow_layers:
		var t := float(i) / float(maxi(glow_layers - 1, 1))
		var w := (1.5 + t * glow_spread) * pulse
		glow.a = (1.0 - t) * 0.22
		_stroke(pts, w, glow)

	# Bright, near-white-but-still-entity-tinted core.
	var core := entity_tint.lerp(Color.WHITE, core_whiteness)
	if sigil.closed:
		core.a = 0.85
		draw_colored_polygon(pts, core)
	else:
		core.a = 0.95
		_stroke(pts, 1.5 * pulse, core)


func _stroke(pts: PackedVector2Array, width: float, color: Color) -> void:
	var line := pts
	if sigil.closed:
		line = pts.duplicate()
		line.append(pts[0])
	draw_polyline(line, color, width, true)


static func _shared_add_material() -> CanvasItemMaterial:
	if _add_material == null:
		_add_material = CanvasItemMaterial.new()
		_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_material
