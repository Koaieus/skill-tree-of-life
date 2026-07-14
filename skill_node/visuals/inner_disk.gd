@tool
extends SkillNodeVisual
## Inner disk: semi-sphere `canvas_item` shader (#123). Filled circle with an
## offset radial highlight, lit in the entity's color when allocated and in a
## dark neutral when not — the dome, its shine and its weld dent draw either
## way, so allocation is a color change, not a topology change. See
## inner_disk.gdshader for the fragment logic.
##
## ONE shared ShaderMaterial across every inner_disk instance (built lazily,
## cached in the static [member _shared_material]) — per-node values ride as
## the shader's `instance uniform`s via
## [method CanvasItem.set_instance_shader_parameter], so many disks on
## screen still batch into a single draw call instead of costing one
## draw call each (which a per-node `resource_local_to_scene` duplicate
## material would). See docs/domain/skill-node-visuals-shaders.md.
##
## Composes the weld glyph directly as a height-field dent in its own shader
## (see inner_disk.gdshader's show_weld/weld_* uniforms and
## lighting.gdshaderinc's sn_polygon_facet/sn_bowl_drop) rather than as a
## separate WeldSymbol node — the glyph used to be a sibling Node2D with its
## own CPU twin of this shading formula; folding it into this same fragment
## shader means it can't drift from the disk's own lighting, by
## construction. See .claude/rules/skill-node-visuals.md.

const SHADER := preload("res://skill_node/visuals/inner_disk.gdshader")

## Placeholder glyph = a regular polygon with this many sides per archetype.
enum Archetype { STR, DEX, INT, WIS, PER, CON }
const ARCH_SIDES := {
	Archetype.STR: 3,
	Archetype.DEX: 4,
	Archetype.INT: 6,
	Archetype.WIS: 5,
	Archetype.PER: 8,
	Archetype.CON: 12,
}

static var _shared_material: ShaderMaterial

## Loot relic gem cut (#168). Baked ONCE into a small shared LUT (see
## _build_diamond_lut) rather than recomputed per-pixel per-instance like the
## weld glyph — every relic wants the exact same table+crown shape, so there's
## nothing to gain from re-deriving it analytically on every node, every
## frame. Geometry constants here MUST mirror
## lighting.gdshaderinc's SN_DIAMOND_DEPTH_SCALE / SN_DIAMOND_GRAD_SCALE (the
## bake and the decode are two halves of one encoding).
const DIAMOND_LUT_SIZE := 128
const DIAMOND_SIDES := 8.0
const DIAMOND_GIRDLE_R := 0.85
const DIAMOND_TABLE_K := 0.5
const DIAMOND_DEPTH := 0.35
const DIAMOND_GRAD_SCALE := 3.0
static var _diamond_lut: ImageTexture

## Saturation of the disk tint (0 = grey, 1 = fully saturated) — the private
## mix against which [member SkillNodeVisual.entity_tint] is blended, the
## disk's counterpart to RimRing's bronze metal.
@export_range(0.0, 1.0, 0.01) var tint_mix: float = 0.6:
	set(value):
		tint_mix = value
		_sync_material()

## Disk radius. Defaults to SkillNode.inner_radius (24) — see
## .claude/rules/skill-node-visuals.md.
@export_range(1.0, 128.0, 0.5) var disk_radius: float = 24.0:
	set(value):
		disk_radius = value
		queue_redraw()

## Offset of the specular highlight in the disk's normalized (-1..1) local
## space. Fixed for now; the shader/uniform split lets this be driven by
## mouse position or a light source later without touching fragment logic.
@export var highlight_position: Vector2 = Vector2(-0.35, -0.35):
	set(value):
		highlight_position = value
		_sync_material()

@export_range(0.0, 1.0, 0.01) var highlight_intensity: float = 0.85:
	set(value):
		highlight_intensity = value
		_sync_material()

## Off by default per the locked design ("showWeld — off is the new default;
## empty center. on restores the archetype shape" — Rim Forge Lab): the disk's
## own semi-sphere shading + specular highlight is the baseline read, the
## glyph is an opt-in accent.
@export var show_weld: bool = false:
	set(value):
		show_weld = value
		if value:
			show_diamond = false
		_sync_material()

## Loot relic gem cut (#168) — mutually exclusive with [member show_weld]
## (only one glyph on screen at a time; diamond wins if both are set). See
## the DIAMOND_* consts above and _build_diamond_lut for the baked shape.
@export var show_diamond: bool = false:
	set(value):
		show_diamond = value
		if value:
			show_weld = false
		_sync_material()

@export var arch: Archetype = Archetype.STR:
	set(value):
		arch = value
		_sync_material()

## Glyph circumradius relative to the disk radius. At 1.0 the glyph's
## vertices sit exactly on the disk's circle.
@export_range(0.4, 1.15, 0.01) var weld_k: float = 0.75:
	set(value):
		weld_k = value
		_sync_material()

## Max depth of the glyph's bowl dent at its own visual center — see
## inner_disk.gdshader/lighting.gdshaderinc's sn_bowl_drop.
@export_range(0.0, 1.0, 0.01) var well_depth: float = 0.35:
	set(value):
		well_depth = value
		_sync_material()

## Width of the hairline traced at the glyph's true (outer) boundary, as a
## fraction of the disk radius.
@export_range(0.0, 0.05, 0.001) var hairline_width: float = 0.015:
	set(value):
		hairline_width = value
		_sync_material()

@export_range(0.0, 1.0, 0.01) var hairline_opacity: float = 0.35:
	set(value):
		hairline_opacity = value
		_sync_material()

## Shared light source (see [LightingStyle]), INJECTED AT RUNTIME by the
## composite — a plain `var`, deliberately NOT `@export`: it holds a
## composite-built resource, and an exported field assigned in a @tool context
## gets baked into the scene by an editor save (the gotcha in
## .claude/rules/skill-node-visuals.md). When null (standalone preview) the
## local highlight_* @exports are edited directly.
var lighting: LightingStyle = null:
	set(value):
		if lighting != null and lighting.changed.is_connected(_apply_lighting):
			lighting.changed.disconnect(_apply_lighting)
		lighting = value
		if lighting != null and not lighting.changed.is_connected(_apply_lighting):
			lighting.changed.connect(_apply_lighting)
		_apply_lighting()


func _apply_lighting() -> void:
	if lighting == null:
		return
	highlight_position = lighting.highlight_position
	highlight_intensity = lighting.highlight_intensity


## The disk is the node's ownership read, so it draws in the entity's color.
func _on_identity_changed() -> void:
	_sync_material()


func _ready() -> void:
	if _shared_material == null:
		_shared_material = ShaderMaterial.new()
		_shared_material.shader = SHADER
	if _diamond_lut == null:
		_diamond_lut = _build_diamond_lut()
	# Plain (non-instance) uniform — the LUT is identical for every InnerDisk,
	# so it's set ONCE on the shared material rather than per-instance. (This is
	# on the SHARED material, so it does NOT claim a per-instance buffer slot —
	# binding `material` on THIS CanvasItem is what does, hence the gate below.)
	_shared_material.set_shader_parameter(&"diamond_lut", _diamond_lut)
	# Re-sync when the disk is shown after being hidden — see the visibility gate
	# in _sync_material (#172). Fires on this node too when an ancestor (a fogged
	# SkillNode, the invisible Node Graph preview graph) toggles visibility.
	visibility_changed.connect(_sync_material)
	_sync_material()


func configure(new_radius: float) -> void:
	super.configure(new_radius)
	disk_radius = new_radius


func _sync_material() -> void:
	if not is_node_ready():
		return
	# Each set_instance_shader_parameter below claims a slot in the shared global
	# instance-uniform buffer — even on a CanvasItem that never renders (#172).
	# A disk on a fog-hidden SkillNode, or on the procgen Node Graph preview's
	# invisible graph, has no reason to hold one; gate on tree visibility and let
	# the visibility_changed re-sync above set the uniforms the frame it shows.
	if not is_visible_in_tree():
		return
	# Bind the shared material HERE (not in _ready): the bind is itself what
	# allocates this instance's uniform-buffer slot, so a hidden/fogged disk that
	# never reaches this line never claims one. Guard the reassign so we don't
	# churn `material` (a property the inspector watches) on every resync.
	if material != _shared_material:
		material = _shared_material
	set_instance_shader_parameter(&"tint_color", entity_tint)
	set_instance_shader_parameter(&"tint_mix", tint_mix)
	set_instance_shader_parameter(&"allocated", allocated)
	set_instance_shader_parameter(&"highlight_position", highlight_position)
	set_instance_shader_parameter(&"highlight_intensity", highlight_intensity)
	set_instance_shader_parameter(&"show_diamond", show_diamond)
	set_instance_shader_parameter(&"show_weld", show_weld)
	set_instance_shader_parameter(&"weld_sides", float(ARCH_SIDES.get(arch, 6)))
	set_instance_shader_parameter(&"weld_k", weld_k)
	set_instance_shader_parameter(&"well_depth", well_depth)
	set_instance_shader_parameter(&"hairline_width", hairline_width)
	set_instance_shader_parameter(&"hairline_opacity", hairline_opacity)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2(-disk_radius, -disk_radius), Vector2.ONE * disk_radius * 2.0), Color.WHITE)


## Bakes the diamond crown's height field into a small shared LUT texture —
## built ONCE (lazily, cached in [member _diamond_lut]) rather than
## recomputed per-pixel in the shader, since the shape is fixed and identical
## across every relic. This GDScript geometry IS the source of truth (the
## shader only decodes it via sn_diamond_bump), not a parallel re-derivation
## of a GPU formula — see the class doc above and lighting.gdshaderinc.
##
## Encoding (must match sn_diamond_bump's decode): R = drop/DIAMOND_DEPTH,
## GB = grad/DIAMOND_GRAD_SCALE remapped -1..1 -> 0..1, A = 1 inside the
## gem's girdle else 0.
##
## Baked WITH mipmaps: the LUT (128px) is higher-resolution than the disk's
## on-screen footprint (~48-64px), so sampling it is a MINIFICATION, not a
## magnification — without mips, bilinear only blends 4 texels per screen
## pixel instead of properly box-filtering the ~2-3 texel neighborhood each
## screen pixel actually covers, aliasing exactly at the facet creases this
## LUT exists to render crisply. `filter_linear_mipmap` on the shader
## uniform (inner_disk.gdshader) is the other half of this fix.
static func _build_diamond_lut() -> ImageTexture:
	var img := Image.create(DIAMOND_LUT_SIZE, DIAMOND_LUT_SIZE, false, Image.FORMAT_RGBA8)
	for y in DIAMOND_LUT_SIZE:
		for x in DIAMOND_LUT_SIZE:
			var u := (float(x) + 0.5) / float(DIAMOND_LUT_SIZE)
			var v := (float(y) + 0.5) / float(DIAMOND_LUT_SIZE)
			var p := (Vector2(u, v) - Vector2(0.5, 0.5)) * 2.0
			var hg := _diamond_height_grad(p)
			var r := hg.x / DIAMOND_DEPTH
			var g := clampf(hg.y / DIAMOND_GRAD_SCALE * 0.5 + 0.5, 0.0, 1.0)
			var b := clampf(hg.z / DIAMOND_GRAD_SCALE * 0.5 + 0.5, 0.0, 1.0)
			var a := 1.0 if hg.x > 0.0 or _diamond_inside_girdle(p) else 0.0
			img.set_pixel(x, y, Color(r, g, b, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Table+crown height/gradient at a normalized (-1..1) disk-space position —
## a flat table facet (constant height, zero gradient) surrounded by
## DIAMOND_SIDES flat crown facets ramping linearly down to 0 at the girdle.
## Deliberately flat per facet (not the weld's curved bowl profile): a linear
## ramp between two nested regular polygons is what reads as a faceted gem
## cut instead of a dent. Returned as Vector3(drop, grad.x, grad.y); zero
## outside the girdle. Mirrors sn_polygon_facet's angle-fold math (see
## lighting.gdshaderinc) but runs once at bake time, not per pixel.
static func _diamond_height_grad(p: Vector2) -> Vector3:
	var sector := TAU / DIAMOND_SIDES
	var raw_angle := atan2(p.y, p.x) + PI * 0.5
	var a := fposmod(raw_angle, sector) - sector * 0.5
	var girdle_apothem := DIAMOND_GIRDLE_R * cos(sector * 0.5)
	var table_apothem := (DIAMOND_GIRDLE_R * DIAMOND_TABLE_K) * cos(sector * 0.5)
	var dist_along := p.length() * cos(a)
	if dist_along - girdle_apothem > 0.0:
		return Vector3.ZERO
	var bisector_angle := raw_angle - a - PI * 0.5
	var n_sector := Vector2(cos(bisector_angle), sin(bisector_angle))
	if dist_along - table_apothem <= 0.0:
		return Vector3(DIAMOND_DEPTH, 0.0, 0.0)
	var t := (dist_along - table_apothem) / (girdle_apothem - table_apothem)
	var drop := DIAMOND_DEPTH * (1.0 - t)
	var slope := DIAMOND_DEPTH / (girdle_apothem - table_apothem)
	var grad := n_sector * -slope
	return Vector3(drop, grad.x, grad.y)


static func _diamond_inside_girdle(p: Vector2) -> bool:
	var sector := TAU / DIAMOND_SIDES
	var raw_angle := atan2(p.y, p.x) + PI * 0.5
	var a := fposmod(raw_angle, sector) - sector * 0.5
	var girdle_apothem := DIAMOND_GIRDLE_R * cos(sector * 0.5)
	return p.length() * cos(a) - girdle_apothem <= 0.0
