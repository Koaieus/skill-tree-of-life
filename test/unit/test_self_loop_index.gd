extends GutTest

## `SkillNode.self_loops` is a DERIVED back-index: each `Edge` with
## `from == to` registers itself there and unregisters when it stops being a
## loop (endpoint reassigned) or leaves the tree. It must never be serialized —
## an editor save once baked `[null, NodePath(...)]`, so `self_loop_count`
## read 2 for one loop and `GraphMirror.get_degree` disagreed with
## `SkillNode.get_graph_degree` by +2.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

const _BAKED_SCENES := [
	"res://scenes/dev_sandbox.tscn",
	"res://addons/spell_playground/playground_panel.tscn",
]

var _graph: Graph


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)


func _add_nodes(count: int) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for i in count:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.add_skill_node(sn)
		out.append(sn)
	return out


func test_self_loops_is_not_a_stored_property() -> void:
	var sn := SkillNode.new()
	autofree(sn)
	for p in sn.get_property_list():
		if p.name == "self_loops":
			assert_eq(p.usage & PROPERTY_USAGE_STORAGE, 0,
				"self_loops is derived; a scene save must not bake it")


func test_no_scene_bakes_self_loops() -> void:
	for path in _BAKED_SCENES:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), "fixture: %s must be readable" % path)
		assert_false(text.contains("self_loops"),
			"%s still bakes the derived self_loops index" % path)


func test_two_real_loops_count_two() -> void:
	var n := _add_nodes(1)
	_graph.add_edge(n[0], n[0])
	_graph.add_edge(n[0], n[0])
	assert_eq(n[0].self_loop_count, 2)


func test_re_adding_the_same_edge_does_not_count_it_twice() -> void:
	var n := _add_nodes(1)
	var e := _graph.add_edge(n[0], n[0])
	_graph.edges_container.remove_child(e)
	_graph.edges_container.add_child(e)
	assert_eq(n[0].self_loop_count, 1, "leaving and re-entering the tree is one loop")


func test_a_freed_loop_stops_counting() -> void:
	var n := _add_nodes(1)
	_graph.add_edge(n[0], n[0])
	var doomed := _graph.add_edge(n[0], n[0])
	doomed.free()  # bypasses Graph.remove_edge on purpose
	assert_eq(n[0].self_loop_count, 1, "a freed edge must not stay in the index")


func test_remove_edge_drops_a_loop_by_exactly_one() -> void:
	var n := _add_nodes(1)
	_graph.add_edge(n[0], n[0])
	var e := _graph.add_edge(n[0], n[0])
	_graph.remove_edge(e)
	assert_eq(n[0].self_loop_count, 1)


func test_reassigning_an_endpoint_unregisters_the_loop() -> void:
	var n := _add_nodes(2)
	var e := _graph.add_edge(n[0], n[0])
	e.to = n[1]
	assert_eq(n[0].self_loop_count, 0, "no longer a loop once `to` moves")
	var f := _graph.add_edge(n[0], n[0])
	f.from = n[1]
	assert_eq(n[0].self_loop_count, 0, "the old `from` loses it when `from` moves")
	f.to = n[1]
	assert_eq(n[1].self_loop_count, 1, "and the new endpoint gains it once it closes")
