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

const SHADER := preload("res://skill_node/visuals/inner_disk.gdshader")

static var _shared_material: ShaderMaterial

## Archetype hue in degrees (0-360). Only visible when [member allocated].
@export_range(0.0, 360.0, 1.0) var hue: float = 220.0:
	set(value):
		hue = value
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
@export var disk_radius: float = 24.0:
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
	set_instance_shader_parameter(&"hue", hue)
	set_instance_shader_parameter(&"tint_mix", tint_mix)
	set_instance_shader_parameter(&"allocated", allocated)
	set_instance_shader_parameter(&"highlight_position", highlight_position)
	set_instance_shader_parameter(&"highlight_intensity", highlight_intensity)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2(-disk_radius, -disk_radius), Vector2.ONE * disk_radius * 2.0), Color.WHITE)
