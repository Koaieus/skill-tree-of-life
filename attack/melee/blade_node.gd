@tool
class_name BladeNode
extends Node2D

## Pure visual — its position is written each playback frame by SkillBlade
## from a BladeTrajectory sample. No physics, no collision.

@export_range(1.0, 100., 1.0) var radius: float = 32.0:
	set(value):
		radius = value
		if is_node_ready():
			_visual.configure(radius, is_pivot)

@export var is_pivot: bool = false:
	set(value):
		is_pivot = value
		if is_node_ready():
			_visual.configure(radius, is_pivot)

@onready var _visual: Node2D = $Visuals/BladeCircle


func _ready() -> void:
	_visual.configure(radius, is_pivot)


## Returns the point on this node's circumference facing `world_target`.
## BladeEdge uses this to trim edges to the rim.
func edge_point(world_target: Vector2) -> Vector2:
	var dir := (world_target - global_position).normalized()
	return global_position + dir * radius


func _to_string() -> String:
	return "<BladeNode>"
