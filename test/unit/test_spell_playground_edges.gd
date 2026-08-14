extends GutTest

## The spell playground's graph edges are SCENE-AUTHORED, not generated.
##
## They used to be built at `_ready` by `_build_grid_edges()`, which bailed on
##     if not graph.get_edges().is_empty(): return
## so authoring any single Edge into the scene silently suppressed all 27
## generated ones — the "adding one self-loop made every other edge vanish" bug.
## The generator is gone; these assertions are what stops the topology from
## being quietly lost in a future scene edit.

const _PANEL := preload("res://addons/spell_playground/playground_panel.tscn")

var _graph: Node


func before_each() -> void:
	var panel := _PANEL.instantiate()
	add_child_autofree(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	_graph = panel.find_child("Graph", true, false)
	assert_not_null(_graph, "fixture: the panel must carry a Graph")


func test_scene_authors_the_full_grid_topology() -> void:
	var edges: Array = _graph.get_edges()
	# 4x4 cardinal grid (24) - 2 skipped cardinals + 5 extra diagonals = 27,
	# plus the authored self-loop on T_12.
	assert_eq(edges.size(), 28, "authored edge count drifted from the scene")
	assert_eq(_graph.get_node("Nodes").get_child_count(), 16)


func test_every_authored_edge_resolves_both_endpoints() -> void:
	for e in _graph.get_edges():
		assert_not_null(e.from, "%s has an unresolved `from` NodePath" % e.name)
		assert_not_null(e.to, "%s has an unresolved `to` NodePath" % e.name)


## `self_loops` is a DERIVED runtime index that the editor serializes anyway
## (audit finding C7). A save had baked `[null, NodePath(...)]` onto T_12 — one
## real entry plus a null — which makes `self_loop_count` report 2 for a single
## loop, and `GraphMirror.get_degree` adds `2 * self_loop_count`, so the node's
## degree came out +2 too high while `Graph._ensure_topology` counted it right.
## Two disagreeing degree answers feed spell `min_degree` gating.
func test_the_one_self_loop_counts_once() -> void:
	var t12 := _graph.get_node("Nodes/T_12")
	assert_eq(t12.self_loop_count, 1,
		"a null entry baked into the exported `self_loops` array inflates this")
	for sl in t12.self_loops:
		assert_not_null(sl, "no null may sit in the self_loops index")


## The degree the gameplay rules read must agree with the topology the scene
## authors — this is the assertion that would have caught the baked null.
func test_degree_agrees_with_the_authored_topology() -> void:
	var t12 := _graph.get_node("Nodes/T_12")
	# T_12 is row 1, col 2 -> linear index 6. Cardinal neighbours 2, 5, 7, 10,
	# plus the authored (3,6) cross-link near the NE corner = 5 real edges.
	# A self-loop counts +2 (see .claude/rules/degree.md), so 5 + 2 = 7.
	assert_eq(t12.get_graph_degree(_graph), 7,
		"5 real edges (+1 each) plus one self-loop (+2)")
