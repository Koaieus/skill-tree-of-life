extends GutTest
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## Deallocation-denied feedback (#89). When a voluntary dealloc is gated away by
## islanding, the nodes that would be cut off from the core are identified (they
## pulse danger-red in-game); the target node gets a "no" shake. This covers the
## logic (which nodes are islanded) + that the SkillNode feedback methods run and
## reset cleanly. The actual blink/shake visuals are verified in-game.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_nodes = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	_add_edge(_nodes[0], _nodes[1])  # line: core(N0) – N1 – N2
	_add_edge(_nodes[1], _nodes[2])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)
	await get_tree().process_frame

	for n in _nodes:
		_alloc.force_allocate(_entity, n)
	_entity.core_location = _nodes[0]


func after_each() -> void:
	pass


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


func test_removing_cut_vertex_islands_the_tail() -> void:
	# Dropping N1 (the cut vertex) would strand N2 from the core N0.
	var islanded := _entity.navigator.nodes_islanded_by_removing(_nodes[1], _entity.core_location)
	assert_eq(islanded.size(), 1, "one node stranded")
	assert_true(_nodes[2] in islanded, "N2 is cut off from the core when N1 goes")
	assert_false(_nodes[0] in islanded, "the core itself is never islanded")


func test_removing_leaf_islands_nothing() -> void:
	# Dropping the leaf N2 strands no one — deallocation would be allowed.
	var islanded := _entity.navigator.nodes_islanded_by_removing(_nodes[2], _entity.core_location)
	assert_eq(islanded.size(), 0, "leaf removal islands nobody")


func test_deallocate_of_cut_vertex_is_denied() -> void:
	# The gate that triggers the feedback path.
	assert_false(_alloc.can_deallocate(_nodes[1], _entity), "cut vertex is non-islanding-denied")
	assert_true(_alloc.can_deallocate(_nodes[2], _entity), "leaf is deallocatable")


func test_feedback_methods_run_and_reset() -> void:
	# Visual smoke: methods run without error, tween the visuals, and leave the
	# node reset (no stuck offset/tint) after killing via a re-trigger.
	var n := _nodes[2]
	n.blink_blocked()
	n.shake_denied()  # re-trigger kills the blink and resets before shaking
	n.shake_denied()  # spam-safe
	# Force the reset path directly and assert clean state.
	n._reset_feedback()
	assert_eq(n.visuals.position, Vector2.ZERO, "shake offset reset")
	assert_eq(n.hover_ring.position, Vector2.ZERO, "counter-translated glow reset")
	assert_eq(n._node_visuals.feedback_tint, Color.WHITE, "danger tint reset (on body, not visuals)")
