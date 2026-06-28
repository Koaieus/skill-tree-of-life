@tool
extends Node2D

@export var color: Color = Color.YELLOW_GREEN

var _radius: float = 32.0

# Hover band (ring convention — see SkillNode.ring_centerline): sits flush
# OUTSIDE the node boundary (inner edge at `radius`, outer edge `radius + 8`).
const HOVER_INNER_OFFSET: float = 0.0
const HOVER_WIDTH: float = 8.0

func configure(r: float) -> void:
	_radius = r
	queue_redraw()


func _draw() -> void:
	var c := SkillNode.ring_centerline(_radius, HOVER_INNER_OFFSET, HOVER_WIDTH)
	draw_circle(Vector2.ZERO, c, color, false, HOVER_WIDTH, true)
