extends GutTest

## `Graph.get_node_bounds()` — the AABB helper GameRoot grows into the camera
## pan limit / fog-of-war rect. Pure geometry, so it earns its own test rather
## than only being exercised through GameRoot.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

var _graph: Graph


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)


func _add_node_at(pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.global_position = pos
	_graph.skill_nodes_container.add_child(sn)
	return sn


func test_empty_graph_returns_zero_rect() -> void:
	var bounds := _graph.get_node_bounds()
	assert_eq(bounds, Rect2())


func test_single_node_returns_zero_size_rect_at_its_position() -> void:
	_add_node_at(Vector2(50, -30))
	var bounds := _graph.get_node_bounds()
	assert_eq(bounds.position, Vector2(50, -30))
	assert_eq(bounds.size, Vector2.ZERO)


func test_bounds_expands_to_every_node() -> void:
	_add_node_at(Vector2(-100, 20))
	_add_node_at(Vector2(300, -50))
	_add_node_at(Vector2(10, 400))

	var bounds := _graph.get_node_bounds()
	assert_eq(bounds.position, Vector2(-100, -50))
	assert_eq(bounds.end, Vector2(300, 400))
