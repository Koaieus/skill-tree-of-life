@tool
extends SkillNodeVisual
## Inner disk: semi-sphere `canvas_item` shader (#123). Filled circle with an
## offset radial highlight, player-tinted when allocated, neutral-dark when
## not. See inner_disk.gdshader for the fragment logic.
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

## The allocating entity's color (or the archetype color in a standalone
## preview). Only visible when [member allocated] — unallocated nodes stay
## neutral-dark regardless of this value, so there's no hue-extraction step
## anywhere: the color IS what gets drawn, not a derived hint.
@export var tint_color: Color = Color(0.291, 0.5892, 1.0):
	set(value):
		tint_color = value
		_sync_material()

## Saturation of the metal/disk tint (0 = grey, 1 = fully saturated).
@export_range(0.0, 1.0, 0.01) var tint_mix: float = 0.6:
	set(value):
		tint_mix = value
		_sync_material()

## Swaps tinted gradient (true) vs neutral-dark gradient (false); allocated
## nodes also read as "owned" via the brighter tint.
@export var allocated: bool = false:
	set(value):
		allocated = value
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

## Shared shading source (see [ShadingStyle]), INJECTED AT RUNTIME by the
## composite — a plain `var`, deliberately NOT `@export`: it holds a
## composite-built resource, and an exported field assigned in a @tool context
## gets baked into the scene by an editor save (the gotcha in
## .claude/rules/skill-node-visuals.md). When set its fields drive the five
## knobs above via one `changed` connection; when null (standalone preview) the
## local @exports are edited directly.
var shading: ShadingStyle = null:
	set(value):
		if shading != null and shading.changed.is_connected(_apply_shading):
			shading.changed.disconnect(_apply_shading)
		shading = value
		if shading != null and not shading.changed.is_connected(_apply_shading):
			shading.changed.connect(_apply_shading)
		_apply_shading()


func _apply_shading() -> void:
	if shading == null:
		return
	tint_color = shading.tint_color
	tint_mix = shading.tint_mix
	allocated = shading.allocated
	highlight_position = shading.highlight_position
	highlight_intensity = shading.highlight_intensity


func _ready() -> void:
	if _shared_material == null:
		_shared_material = ShaderMaterial.new()
		_shared_material.shader = SHADER
	material = _shared_material
	_sync_material()


func configure(new_radius: float) -> void:
	super.configure(new_radius)
	disk_radius = new_radius


func _sync_material() -> void:
	if not is_node_ready():
		return
	set_instance_shader_parameter(&"tint_color", tint_color)
	set_instance_shader_parameter(&"tint_mix", tint_mix)
	set_instance_shader_parameter(&"allocated", allocated)
	set_instance_shader_parameter(&"highlight_position", highlight_position)
	set_instance_shader_parameter(&"highlight_intensity", highlight_intensity)
	set_instance_shader_parameter(&"show_weld", show_weld)
	set_instance_shader_parameter(&"weld_sides", float(ARCH_SIDES.get(arch, 6)))
	set_instance_shader_parameter(&"weld_k", weld_k)
	set_instance_shader_parameter(&"well_depth", well_depth)
	set_instance_shader_parameter(&"hairline_width", hairline_width)
	set_instance_shader_parameter(&"hairline_opacity", hairline_opacity)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2(-disk_radius, -disk_radius), Vector2.ONE * disk_radius * 2.0), Color.WHITE)
