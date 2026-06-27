@tool
class_name Floater
extends Node2D

## A single floating world-space number: owns its text/color, its drift+fade
## tuning, AND its animation. Spawned + configured by [FloatingNumberLayer.spawn];
## also previewable in the editor via the Animate tool button (it replays in
## place instead of freeing itself).

@export var float_distance: float = 70.0
@export var float_time: float = 3.0
@export var font_size: int = 36
@export var outline_size: int = 6
## Degrees of drift-angle wiggle (0 = straight up). Was a layer-wide knob; now
## per-floater so a future "burst" floater can wiggle without touching others.
@export_range(0, 90) var max_angle: int = 0
@export var text: String = "123":
	set(value):
		text = value
		queue_redraw()
@export var fill_color: Color = Color.WHITE:
	set(value):
		fill_color = value
		queue_redraw()
@export_tool_button("Animate") var _animate_button := animate

const _OUTLINE_COLOR := Color(0.1, 0.0, 0.0, 1.0)

var alpha: float = 1.0:
	set(value):
		alpha = value
		queue_redraw()

var _font: Font
var _anim_origin: Vector2 = Vector2.ZERO


func _ready() -> void:
	_font = ThemeDB.fallback_font
	queue_redraw()


## Drift up + fade out from the current position, then free (runtime) or reset
## for replay (editor). The layer sets [member Node2D.global_position] first.
func animate() -> void:
	_anim_origin = position
	alpha = 1.0
	rotation_degrees = 0.0
	var dir := randi_range(-max_angle, max_angle)
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "position",
		_anim_origin + Vector2(0.0, -float_distance).rotated(deg_to_rad(dir)), float_time)
	t.tween_property(self, "alpha", 0.0, float_time)
	t.tween_property(self, "rotation_degrees", float(dir), float_time)
	t.chain().tween_callback(_on_anim_done)


func _on_anim_done() -> void:
	if Engine.is_editor_hint():
		position = _anim_origin
		alpha = 1.0
		rotation_degrees = 0.0
		return
	queue_free()


func _draw() -> void:
	if _font == null or text.is_empty():
		return
	var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos := Vector2(-text_size.x * 0.5, text_size.y * 0.25)
	var fill := Color(fill_color.r, fill_color.g, fill_color.b, alpha)
	var outline := Color(_OUTLINE_COLOR.r, _OUTLINE_COLOR.g, _OUTLINE_COLOR.b, alpha)
	draw_string_outline(_font, pos, text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, outline_size, outline)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, fill)
