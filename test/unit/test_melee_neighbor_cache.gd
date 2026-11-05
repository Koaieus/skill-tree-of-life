extends GutTest

## _is_neighbor_of_blade_set answers from Graph.get_neighbours (cached
## adjacency), not a per-node walk of every edge. Characterization on a
## chain + branch, and after the blade shrinks.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

const _GRAPH_SCENE := preload("res://graph/graph.tscn")


class SpyGraph extends Graph:
	var edge_walks := 0

	func get_edges() -> Array[Edge]:
		edge_walks += 1
		return super.get_edges()


var _graph: Graph


func _spawn(nm: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	return sn


func test_neighbor_predicate_tracks_blade_set() -> void:
	var g := _GRAPH_SCENE.instantiate() as Graph
	g.set_script(SpyGraph)
	add_child_autofree(g)
	_graph = g
	var alloc := TestWorld.around(_graph).allocator()
	var ent := Entity.new()
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	ent.stat_board.blade_size.base_value = 3.0
	_graph.add_child(ent)
	var a := _spawn("A")
	var b := _spawn("B")
	var c := _spawn("C")
	var d := _spawn("D")
	var far := _spawn("Far")
	_graph.add_edge(a, b)
	_graph.add_edge(b, c)
	_graph.add_edge(b, d)
	await get_tree().process_frame
	for n in [a, b, c]:
		alloc.force_allocate(ent, n)
	var plan := autofree(MeleeAttackPlan.new()) as MeleeAttackPlan
	plan.attacker = ent
	plan.set_pivot(a)
	plan.toggle_member(b)
	assert_true(plan._is_neighbor_of_blade_set(c), "chain: C touches member B")
	assert_true(plan._is_neighbor_of_blade_set(d), "branch: D touches member B")
	assert_false(plan._is_neighbor_of_blade_set(far), "isolated node")
	plan.toggle_member(b)
	assert_false(plan._is_neighbor_of_blade_set(c), "blade shrank: C only touches B")
	assert_true(plan._is_neighbor_of_blade_set(b), "B touches pivot A")
	var spy := _graph as SpyGraph
	spy.edge_walks = 0
	for n in [a, b, c, d, far]:
		plan.get_node_role(n)
	assert_eq(spy.edge_walks, 0, "get_node_role must not walk every edge per node")
