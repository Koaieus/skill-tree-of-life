extends GutTest

## `Graph.stable_id` / `get_by_stable_id` — O(1) node identity that survives
## a container-index shift (a removal reshuffles children; stable_id is
## assigned once and never reused).

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

var _graph: Graph


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)


func _new_node() -> SkillNode:
	return _SKILL_NODE_SCENE.instantiate() as SkillNode


func test_added_node_gets_a_nonzero_stable_id() -> void:
	var sn := _new_node()
	_graph.add_skill_node(sn)

	assert_ne(sn.stable_id, 0)


func test_two_nodes_get_distinct_ids() -> void:
	var a := _new_node()
	var b := _new_node()
	_graph.add_skill_node(a)
	_graph.add_skill_node(b)

	assert_ne(a.stable_id, b.stable_id)


func test_get_by_stable_id_resolves_to_the_right_node() -> void:
	var a := _new_node()
	var b := _new_node()
	_graph.add_skill_node(a)
	_graph.add_skill_node(b)

	assert_eq(_graph.get_by_stable_id(a.stable_id), a)
	assert_eq(_graph.get_by_stable_id(b.stable_id), b)


func test_unknown_id_returns_null() -> void:
	assert_null(_graph.get_by_stable_id(999999))


func test_id_survives_removal_of_an_earlier_sibling_reshuffling_the_container() -> void:
	var a := _new_node()
	var b := _new_node()
	var c := _new_node()
	_graph.add_skill_node(a)
	_graph.add_skill_node(b)
	_graph.add_skill_node(c)

	var c_id := c.stable_id
	_graph.remove_skill_node(a)

	assert_eq(_graph.get_by_stable_id(c_id), c)


func test_removed_id_is_not_reused_by_a_freshly_added_node() -> void:
	var a := _new_node()
	_graph.add_skill_node(a)
	var a_id := a.stable_id
	_graph.remove_skill_node(a)

	var b := _new_node()
	_graph.add_skill_node(b)

	assert_ne(b.stable_id, a_id)
	assert_null(_graph.get_by_stable_id(a_id))
	assert_eq(_graph.get_by_stable_id(b.stable_id), b)
