@tool
extends Node2D

@export var color: Color = Color.YELLOW_GREEN

var _radius: float = 32.0

const HOVER_RING_OFFSET: float = 0.
const HOVER_RING_WIDTH: float = 8.

const RING_OUTSET: float = HOVER_RING_OFFSET + HOVER_RING_WIDTH/2

func configure(r: float) -> void:
	_radius = r
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, _radius + RING_OUTSET, color, false, HOVER_RING_WIDTH, true)
