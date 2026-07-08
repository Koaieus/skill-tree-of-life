extends GutTest

## Sensed-traversal coverage for [VisionSystem], plus the [Graph] adjacency
## index [method Graph.get_neighbours] reads.
##
## The traversal is a max-budget priority walk implemented as a bucket sort
## (budget → nodes reached with that many hops left). These tests pin the
## observable contract: reach = budget in hops, owned/visible nodes are never
## "sensed", multiple sources union their reach, and a stronger source
## dominates a weaker one that would otherwise stop short.
##
## Nodes are placed 2000px apart so the default `vision_range` (~504px) only
## ever reaches a node's own position — that isolates sensing from vision.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

const _SPACING := 2000.0

var _graph: Graph
var _alloc: AllocationSystem
var _vision: VisionSystem
var _entity: Entity
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	# Path graph: N0 – N1 – N2 – N3 – N4
	_nodes = []
	for i in 5:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(i * _SPACING, 0.0)
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	for i in 4:
		_add_edge(_nodes[i], _nodes[i + 1])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.stat_board = _BOARD.duplicate(true) as StatBoard
	_graph.add_child(_entity)
	await get_tree().process_frame

	_vision = VisionSystem.new()
	_vision.graph = _graph
	add_child_autofree(_vision)
	await get_tree().process_frame


func _add_edge(a: SkillNode, b: SkillNode) -> Edge:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)
	return e


## `sensor_range` is a derived stat (the board adds a PER-scaled term on top of
## `base_value`), so setting the base doesn't set the hop budget. Solve for the
## base that lands the *effective* local value on `hops`. Requires the node to
## already be owned — `get_local_value` reads through the owner's board.
func _set_budget(hops: int) -> void:
	var s: Stat = _entity.stat_board.get_stat(&"sensor_range")
	s.base_value = 0.0
	var derived: float = float(_nodes[0].get_local_value(&"sensor_range"))
	s.base_value = float(hops) - derived
	assert_eq(int(_nodes[0].get_local_value(&"sensor_range")), hops,
		"fixture: effective sensor_range should be %d hops" % hops)


## Own `owned_indices`, sense with `hops` budget. Returns sensed node names.
func _sensed_names(hops: int, owned_indices: Array = [0]) -> Array:
	for i in owned_indices:
		_alloc.force_allocate(_entity, _nodes[i])
	_set_budget(hops)
	_vision.viewers = [_entity]
	_vision._recompute()
	var out: Array = []
	for n in _nodes:
		if _vision.is_sensed(n):
			out.append(String(n.name))
	return out


func test_sensed_reach_equals_hop_budget() -> void:
	assert_eq(_sensed_names(2), ["N1", "N2"],
		"2 hops from N0 senses N1 and N2, stops before N3")


func test_zero_budget_senses_nothing() -> void:
	assert_eq(_sensed_names(0), [], "no sensor budget senses nothing")


func test_owned_node_is_visible_not_sensed() -> void:
	_sensed_names(2)
	assert_true(_vision.is_visible(_nodes[0]), "the owned source is visible")
	assert_false(_vision.is_sensed(_nodes[0]), "an owned node is never merely sensed")


func test_multiple_sources_union_their_reach() -> void:
	# Own both ends of the path with 1 hop each: N0 reaches N1, N4 reaches N3.
	# N2 sits 2 hops from either and stays unsensed.
	assert_eq(_sensed_names(1, [0, 4]), ["N1", "N3"],
		"each source contributes its own 1-hop ring")


func test_budget_is_spent_per_hop_from_the_source() -> void:
	# 3 hops from N0 reaches N3 but not N4. If an intermediate node re-seeded
	# the walk with a fresh budget, N4 would leak in.
	assert_eq(_sensed_names(3), ["N1", "N2", "N3"],
		"the walk decays one hop at a time and stops exactly at the budget")


# ── Graph adjacency index ─────────────────────────────────────────────────

func test_neighbours_of_path_interior_and_ends() -> void:
	assert_eq(_graph.get_neighbours(_nodes[0]), [_nodes[1]] as Array[SkillNode])
	assert_eq(_graph.get_neighbours(_nodes[2]), [_nodes[1], _nodes[3]] as Array[SkillNode])


func test_adjacency_index_refreshes_after_edge_added() -> void:
	_add_edge(_nodes[0], _nodes[4])
	assert_eq(_graph.get_neighbours(_nodes[0]), [_nodes[1], _nodes[4]] as Array[SkillNode],
		"a new edge invalidates the cached adjacency")


func test_adjacency_index_refreshes_after_edge_removed() -> void:
	assert_eq(_graph.get_neighbours(_nodes[1]).size(), 2, "seeded before removal")
	_graph.remove_edge(_graph.get_edges()[0])  # N0 – N1
	assert_eq(_graph.get_neighbours(_nodes[1]), [_nodes[2]] as Array[SkillNode],
		"a removed edge invalidates the cached adjacency")
	assert_eq(_graph.get_neighbours(_nodes[0]), [] as Array[SkillNode])


func test_self_loop_counts_each_endpoint_independently() -> void:
	_add_edge(_nodes[0], _nodes[0])
	assert_eq(_graph.get_neighbours(_nodes[0]), [_nodes[1], _nodes[0], _nodes[0]] as Array[SkillNode],
		"a self-loop contributes the node twice (degree +2)")


func test_returned_neighbours_are_not_the_cached_array() -> void:
	var first := _graph.get_neighbours(_nodes[2])
	first.clear()
	assert_eq(_graph.get_neighbours(_nodes[2]).size(), 2,
		"mutating a returned array must not corrupt the index")
