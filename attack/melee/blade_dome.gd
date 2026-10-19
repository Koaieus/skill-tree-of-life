@tool
class_name BladeDome
extends Node2D

## The steel dome body of one [BladeNode] (#1692) — a lit hemisphere drawn by
## `blade_dome.gdshader`. Draws only: every colour and shape number comes from
## the [BladeStyle] its [BladeNode] pushes down through [method configure].
##
## Material shape mirrors [InnerDisk]: ONE static shared [ShaderMaterial] for
## every dome, per-node values as `instance uniform`s — never a per-node
## material (`.claude/rules/rendering-performance.md`). The bind and the
## uniforms are gated on tree visibility, since each claims a slot in the
## global instance-uniform buffer even on a CanvasItem that never renders.

const SHADER: Shader = preload("res://attack/melee/blade_dome.gdshader")

static var _shared_material: ShaderMaterial

var _radius: float = 24.0
var _is_pivot: bool = false
var _style: BladeStyle = null
var _tint: Color = Color.TRANSPARENT


func _ready() -> void:
	if _shared_material == null:
		_shared_material = ShaderMaterial.new()
		_shared_material.shader = SHADER
	visibility_changed.connect(_sync_material)
	_sync_material()


## [param dead] hides the dome outright — a popped vertex's [ShatterField]
## shards take over, the same gate [BladeCircle] draws by.
func configure(r: float, pivot: bool, style: BladeStyle, tint: Color, dead: bool) -> void:
	_radius = r
	_is_pivot = pivot
	_style = style
	_tint = tint
	visible = not dead
	_sync_material()


func _sync_material() -> void:
	if not is_node_ready() or _style == null or not is_visible_in_tree():
		return
	if material != _shared_material:
		material = _shared_material
	set_instance_shader_parameter(&"base_color", _style.dome_color(_is_pivot, _tint, false))
	set_instance_shader_parameter(&"highlight_intensity", _style.dome_highlight_intensity)
	set_instance_shader_parameter(&"highlight_sharpness", _style.dome_highlight_sharpness)
	set_instance_shader_parameter(&"streak_stretch", _style.dome_streak_stretch)
	set_instance_shader_parameter(&"streak_angle", deg_to_rad(_style.dome_streak_angle_deg))
	set_instance_shader_parameter(&"light_dir", _style.dome_light_dir)
	queue_redraw()


func _draw() -> void:
	if _style == null:
		return
	draw_rect(Rect2(Vector2(-_radius, -_radius), Vector2.ONE * _radius * 2.0),
			Color(1.0, 1.0, 1.0, _style.fill_alpha))
