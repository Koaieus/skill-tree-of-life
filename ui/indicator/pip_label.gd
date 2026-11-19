@tool
class_name IndicatorPipLabel
extends Node2D

## The "+N" overclock pip — an indicator part. Its owner pushes the text, the
## colour, the size and where it sits; the role's tint still arrives through
## the inherited modulate and multiplies [member color]. Draws nothing on an
## empty [member text].

@export var text: String = "":
	set(value):
		text = value
		queue_redraw()
@export var color: Color = Color.WHITE:
	set(value):
		color = value
		queue_redraw()
@export var font_size: int = 14:
	set(value):
		font_size = value
		queue_redraw()


func _draw() -> void:
	if text.is_empty():
		return
	var font := ThemeDB.fallback_font
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, Vector2(-size.x * 0.5, font.get_ascent(font_size) * 0.5),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
