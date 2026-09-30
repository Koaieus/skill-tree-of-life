extends GutTest

## Gate core (#1205): a flip is a real edge add/remove, and the control rule is
## an identity question on the far endpoint.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _me: Entity
var _other: Entity
var _nodes: Dictionary


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes = {}
	for id in ["A", "B", "C", "N", "M", "O", "P"]:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = id
		_graph.add_skill_node(sn)
		_nodes[id] = sn
	_graph.add_edge(_n("A"), _n("B"))
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	_alloc.navigator = _graph.navigator
	add_child_autofree(_alloc)
	_me = _entity("Me")
	_other = _entity("Other")
	await get_tree().process_frame
	_me.core_location = _n("A")
	_alloc.force_allocate(_me, _n("A"))
	_alloc.force_allocate(_me, _n("B"))
	_other.core_location = _n("O")
	_alloc.force_allocate(_other, _n("O"))
	_alloc.force_allocate(_other, _n("P"))
	_me.stat_board.skill_points.grant(5)


func _entity(label: String) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.display_name = label
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(e)
	return e


func _n(id: String) -> SkillNode:
	return _nodes[id]


func _flip(gate: Gate) -> void:
	var gates: Array[Gate] = [gate]
	_graph.flip_gates(gates)


# ── Flip = real edge ────────────────────────────────────────────────────────

func test_flipping_an_open_gate_removes_the_edge() -> void:
	_graph.add_edge(_n("B"), _n("C"))
	var gate := _graph.add_gate(_n("A"), _n("C"), true)
	assert_not_null(_graph.edge_between(_n("C"), _n("A")), "open = a real edge, either direction")
	assert_true(gate.is_open())
	assert_eq(_graph.navigator.path_between(_n("A"), _n("C")).size(), 2, "direct hop while open")
	_flip(gate)
	assert_null(_graph.edge_between(_n("A"), _n("C")), "closed = no edge")
	assert_false(gate.is_open())
	assert_false(_graph.get_neighbours(_n("A")).has(_n("C")))
	assert_eq(_n("C").get_graph_degree(_graph), 1, "degree follows the removed edge")
	assert_eq(_graph.navigator.path_between(_n("A"), _n("C")).size(), 3,
			"navigator routes around the closed gate")


func test_flipping_a_closed_gate_creates_the_edge() -> void:
	var gate := _graph.add_gate(_n("B"), _n("C"), false)
	assert_false(gate.is_open())
	assert_eq(_graph.gate_between(_n("C"), _n("B")), gate, "gate_between is direction-free")
	_flip(gate)
	assert_true(gate.is_open())
	assert_not_null(_graph.edge_between(_n("B"), _n("C")))
	assert_true(_graph.get_neighbours(_n("C")).has(_n("B")))
	assert_eq(_n("C").get_graph_degree(_graph), 1)
	assert_eq(_graph.navigator.path_between(_n("A"), _n("C")).size(), 3)


# ── can_toggle ──────────────────────────────────────────────────────────────

func test_can_toggle_mine_mine() -> void:
	assert_true(_graph.add_gate(_n("A"), _n("B"), false).can_toggle(_me))


func test_can_toggle_mine_neutral() -> void:
	assert_true(_graph.add_gate(_n("B"), _n("N"), false).can_toggle(_me))
	assert_true(_graph.add_gate(_n("M"), _n("A"), false).can_toggle(_me), "either end")


func test_cannot_toggle_neutral_neutral() -> void:
	assert_false(_graph.add_gate(_n("N"), _n("M"), false).can_toggle(_me))


func test_cannot_toggle_mine_other() -> void:
	assert_false(_graph.add_gate(_n("B"), _n("O"), false).can_toggle(_me))


func test_cannot_toggle_other_other() -> void:
	assert_false(_graph.add_gate(_n("O"), _n("P"), false).can_toggle(_me))


# ── Wormhole ────────────────────────────────────────────────────────────────

func test_opening_a_gate_onto_a_neutral_node_makes_it_allocatable() -> void:
	var gate := _graph.add_gate(_n("B"), _n("N"), false)
	assert_false(_alloc.can_allocate(_n("N"), _me), "not adjacent while closed")
	var gates: Array[Gate] = [gate]
	_alloc.apply_gate_flip(gates, _me)
	assert_true(_alloc.can_allocate(_n("N"), _me), "the open gate borders it")
