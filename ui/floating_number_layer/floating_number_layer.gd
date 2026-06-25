class_name DamageNumberLayer
extends Node2D

## Floating damage numbers. Spawns a small custom-drawn label at a node's
## position whenever [signal Events.skill_node_damaged] fires; tweens it up
## and fades it out.
##
## Subscribes globally — completely decoupled from the source of damage.
## A spell, a falling trap, a thorn aura — anything that calls
## [method SkillNode.take_damage] gets the same UI feedback for free.

const FLOAT_DISTANCE: float = 40.0
const FLOAT_TIME: float = 0.9
const FONT_SIZE: int = 28
const TEXT_COLOR: Color = Color(1.0, 0.85, 0.85, 1.0)
const OUTLINE_COLOR: Color = Color(0.25, 0.0, 0.0, 1.0)
const OUTLINE_SIZE: int = 6
const MAX_ANGLE: int = 30  # degrees

func _ready() -> void:
	Events.skill_node_damaged.connect(_on_damage)
	z_index = 2000


func _on_damage(node: SkillNode, amount: float, _source: Variant) -> void:
	if node == null or amount <= 0.0:
		return
	var floater := _DamageFloater.new()
	floater.text = "%d" % int(round(amount))
	floater.global_position = node.global_position
	add_child(floater)
	var t := create_tween().set_parallel(true)
	var rng_dir := randi_range(-MAX_ANGLE, MAX_ANGLE)
	t.tween_property(floater, "position",
		floater.position + Vector2(0.0, -FLOAT_DISTANCE).rotated(deg_to_rad(rng_dir)), FLOAT_TIME)
	t.tween_property(floater, "alpha", 0.0, FLOAT_TIME)
	t.tween_property(floater, "rotation_degrees", rng_dir, FLOAT_TIME)
	t.chain().tween_callback(floater.queue_free)


## Inline helper — a Node2D that draws a single string centered on its origin
## with a dark outline. Kept private to the layer because nothing else should
## spawn these directly (route via the global signal instead).
class _DamageFloater extends Node2D:
	var text: String = ""
	var alpha: float = 1.0:
		set(value):
			alpha = value
			queue_redraw()
	var _font: Font

	func _ready() -> void:
		_font = ThemeDB.fallback_font
		queue_redraw()

	func _draw() -> void:
		if _font == null or text.is_empty():
			return
		var size := FONT_SIZE
		var text_size := _font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
		var pos := Vector2(-text_size.x * 0.5, text_size.y * 0.25)
		var fill := Color(
			TEXT_COLOR.r,
			TEXT_COLOR.g,
			TEXT_COLOR.b,
			alpha)
		var outline := Color(
			OUTLINE_COLOR.r,
			OUTLINE_COLOR.g,
			OUTLINE_COLOR.b,
			alpha)
		draw_string_outline(_font, pos, text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, size,
			OUTLINE_SIZE, outline)
		draw_string(_font, pos, text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, size, fill)
