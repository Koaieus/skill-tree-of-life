extends GutTest

## `Navigator` (the base `GraphMirror` wired to every `Graph.tscn`'s
## `$Navigator`, per graph.gd:25) had never been instantiated in a test —
## it only appeared in comments explaining why other fixtures bypass it
## (test_node_regen.gd, test_aura_effect.gd). These exercise the SCENE's real
## Navigator (`graph.navigator`), with no Entity/AllocationSystem/aura
## scaffolding involved, so coverage matches what production code actually
## gets.
##
## Populate via Graph.add_skill_node / Graph.add_edge only — the containers
## don't emit signals, so graph.navigator never mirrors a direct child add
## and every query would silently return empty. See .claude/rules/graph.md.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

var _graph: Graph


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	await get_tree().process_frame  # Navigator._ready wires to the graph


func _add_node(pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.global_position = pos
	_graph.add_skill_node(sn)
	return sn


func test_navigator_mirrors_nodes_and_edges_with_no_entity_or_aura_scaffolding() -> void:
	var a := _add_node(Vector2(0, 0))
	var b := _add_node(Vector2(10, 0))
	_graph.add_edge(a, b)
	await get_tree().process_frame

	var mirrored := _graph.navigator.get_mirrored_nodes()
	assert_true(mirrored.has(a), "a is mirrored")
	assert_true(mirrored.has(b), "b is mirrored")
	assert_eq(_graph.navigator.get_degree(a), 1)
	assert_eq(_graph.navigator.get_degree(b), 1)


## The Navigator is already wired (before_each awaited its own `_ready`)
## before this node is even created — this is the "added after the navigator
## exists" case the issue calls out.
func test_node_added_after_navigator_already_exists_is_picked_up() -> void:
	var late := _add_node(Vector2(50, 50))
	await get_tree().process_frame

	assert_true(_graph.navigator.get_mirrored_nodes().has(late))
	assert_ne(_graph.navigator.vertex_id(late), -1)


func test_navigator_bookkeeping_follows_removal() -> void:
	var a := _add_node(Vector2(0, 0))
	var b := _add_node(Vector2(10, 0))
	_graph.add_edge(a, b)
	await get_tree().process_frame

	# `remove_skill_node` fires `node_removed` (and Navigator's mirror_remove)
	# synchronously, before its own `queue_free()` — don't await a frame here,
	# or `b` is already a freed object by the time these assertions run.
	_graph.remove_skill_node(b)

	assert_false(_graph.navigator.get_mirrored_nodes().has(b))
	assert_eq(_graph.navigator.vertex_id(b), -1)
	assert_eq(_graph.navigator.get_degree(a), 0, "a's edge to the removed node is gone too")
	await get_tree().process_frame  # let the deferred queue_free land before teardown


## Regression pin for the documented adjacency-cache hole
## (.claude/rules/graph.md): the cache invalidates on child add/remove, NOT on
## an `Edge.from`/`to` reassignment on an already-parented edge. Navigator's
## own edge wiring rides on `Graph`'s `edge_added`/`edge_removed` signals
## (fired once, at add-time), so it has the identical blind spot. If this
## test starts failing, `_mark_adjacency_dirty()` (or an equivalent Navigator
## fix) learned to react to endpoint reassignment — update the rule doc to
## match rather than "fixing" this test.
func test_reassigning_a_parented_edges_endpoints_does_not_update_the_mirror() -> void:
	var a := _add_node(Vector2(0, 0))
	var b := _add_node(Vector2(10, 0))
	var c := _add_node(Vector2(20, 0))
	var edge := _graph.add_edge(a, b)
	await get_tree().process_frame

	assert_eq(_graph.navigator.get_degree(a), 1)
	assert_eq(_graph.navigator.get_degree(c), 0)
	# Force Graph's adjacency cache to build NOW, while the edge still points
	# a→b, so the reassignment below is a genuine "stale cache" scenario
	# rather than a first-ever build that would just read the new endpoints.
	assert_true(_graph.get_neighbours(a).has(b), "cache built while the edge is still a→b")

	edge.to = c  # re-point b→c on the already-parented edge; no add/remove
	await get_tree().process_frame

	assert_eq(_graph.navigator.get_degree(c), 0,
			"the mirror still doesn't know about the re-pointed edge — pinned limitation")
	assert_true(_graph.get_neighbours(a).has(b),
			"Graph's own adjacency cache is equally stale here, per .claude/rules/graph.md")
