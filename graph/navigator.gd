@tool
class_name Navigator
extends Node

## Maintains an AStarSkillTree mirroring the Graph's structural state.
## Listens to graph signals; never reaches into the graph. SkillNodes are
## minted a stable integer vertex id on add, freed on remove.
##
## Path queries delegate to `astar` (use the SkillNode → id map via
## `vertex_id(node)` to feed it).

@export var graph: Graph

var astar: AStarSkillTree = AStarSkillTree.new()
var _node_ids: Dictionary[SkillNode, int] = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if graph == null:
		push_warning("Navigator has no Graph reference")
		return
	graph.node_added.connect(_on_node_added)
	graph.node_removed.connect(_on_node_removed)
	graph.edge_added.connect(_on_edge_added)
	graph.edge_removed.connect(_on_edge_removed)


## Vertex id for a SkillNode, or -1 if it isn't in the AStar view.
func vertex_id(node: SkillNode) -> int:
	return _node_ids.get(node, -1)


func _on_node_added(node: SkillNode) -> void:
	if _node_ids.has(node):
		return
	var id := astar.get_available_point_id()
	_node_ids[node] = id
	astar.add_point(id, node.global_position)


func _on_node_removed(node: SkillNode) -> void:
	var id: int = _node_ids.get(node, -1)
	if id < 0:
		return
	astar.remove_point(id)
	_node_ids.erase(node)


func _on_edge_added(edge: Edge) -> void:
	var a := vertex_id(edge.from)
	var b := vertex_id(edge.to)
	if a < 0 or b < 0:
		return
	astar.connect_points(a, b)


func _on_edge_removed(edge: Edge) -> void:
	var a := vertex_id(edge.from)
	var b := vertex_id(edge.to)
	if a < 0 or b < 0:
		return
	if astar.are_points_connected(a, b):
		astar.disconnect_points(a, b)
