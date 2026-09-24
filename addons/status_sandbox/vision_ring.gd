@tool
extends Node2D

## The bench node's vision reach, drawn as a ring. `vision_range` is Euclidean
## scene pixels, read node-locally, so a status that lowers it (blindness)
## shrinks the ring. Redraw is explicit: call [method refresh] when the node's
## statuses or ownership change.

@export var color := Color(0.45, 0.8, 1.0, 0.55)
@export var width := 2.0

var _node: SkillNode = null


func bind(node: SkillNode) -> void:
	_node = node
	refresh()


func refresh() -> void:
	queue_redraw()


## The radius drawn, in scene pixels (0 with no node or no stat).
func get_radius() -> float:
	if _node == null or not is_instance_valid(_node):
		return 0.0
	var v: Variant = _node.get_local_value(&"vision_range")
	return float(v) if v != null else 0.0


func _draw() -> void:
	var r := get_radius()
	if r <= 0.0:
		return
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 128, color, width, true)
