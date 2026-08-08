@tool
extends Node2D

const BORDER_WIDTH: float = 2.0
const FILL_ALPHA: float = 0.7

var _radius: float = 32.0
var _is_pivot: bool = false


func configure(r: float, pivot: bool) -> void:
	_radius = r
	_is_pivot = pivot
	queue_redraw()


func _draw() -> void:
	var base := Color.FIREBRICK if not _is_pivot else Color.CHOCOLATE
	# Thin rim at VALUE (low coverage needs the full stop to read); the fill
	# is a large disk, so it stays a dimmer LABEL step to avoid blowing out
	# at scale (`.claude/rules/skill-node-scale.md`).
	var border := Emissive.at(base, Emissive.VALUE)
	var fill := Emissive.at(base, Emissive.LABEL)
	fill.a = FILL_ALPHA
	draw_circle(Vector2.ZERO, _radius, fill, true)
	draw_circle(Vector2.ZERO, _radius, border, false, BORDER_WIDTH, true)
