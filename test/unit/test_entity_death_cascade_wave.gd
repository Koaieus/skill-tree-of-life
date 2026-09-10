extends GutTest
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## Entity-death cascade wave (#837). `AllocationSystem.deallocate_all_owned`
## force-deallocates a dying entity's whole board un-staggered, core LAST
## (island checks; the only path that ever force-deallocates a core) — but the
## VISUAL wave `BattleSystem._on_entity_dying` announces is core-FIRST,
## rippling outward, reusing the same `cascade_started` signal / `_cascade_layers`
## BFS the node-cascade path already uses. Real-bus fixture (core overflow /
## cascade chip damage), same pattern as `test_entity_death.gd`, so the
## `entity_dying` -> `entity_died` phase ordering runs for real rather than
## being asserted by inspection.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _battle: BattleSystem
var _entity: Entity
var _nodes: Array[SkillNode]  # chain: N0(core,a) - N1(b) - N2(c) - N3(d) - N4(e)
var _waves: Array[Array] = []          # each entry: the `layers` array of one cascade_started emit
var _dealloc_order: Array[SkillNode] = []


func before_each() -> void:
	_waves = []
	_dealloc_order = []

	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_nodes = []
	for i in 5:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	for i in range(_nodes.size() - 1):
		_add_edge(_nodes[i], _nodes[i + 1])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_battle = BattleSystem.new()
	_battle.allocation_system = _alloc
	_battle.graph = _graph
	add_child_autofree(_battle)

	_entity = autofree(Entity.new())
	_entity.display_name = "Victim"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)

	await get_tree().process_frame  # entity._ready: navigator + health.depleted wiring

	for n in _nodes:
		_alloc.force_allocate(_entity, n)
	_entity.core_location = _nodes[0]

	_battle.cascade_started.connect(_on_cascade_started)
	_alloc.force_deallocated.connect(_on_force_deallocated)


func after_each() -> void:
	if _battle.cascade_started.is_connected(_on_cascade_started):
		_battle.cascade_started.disconnect(_on_cascade_started)
	if _alloc.force_deallocated.is_connected(_on_force_deallocated):
		_alloc.force_deallocated.disconnect(_on_force_deallocated)


func _on_cascade_started(layers: Array, _defender: Entity) -> void:
	_waves.append(layers)


func _on_force_deallocated(node: SkillNode, _prev_owner: Entity) -> void:
	_dealloc_order.append(node)


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


func _owned_count() -> int:
	var c := 0
	for n in _graph.get_skill_nodes():
		if n.owned_by == _entity:
			c += 1
	return c


# ── Scenario 1: direct core kill ─────────────────────────────────────────────

func test_core_death_emits_one_core_outward_wave_over_the_whole_board() -> void:
	_entity.stat_board.health.set_current(1.0)
	_nodes[0].take_damage(10000.0, null)  # core overflow -> health 0 -> die()

	assert_eq(_waves.size(), 1, "exactly one wave: the entity-death wave (core overflow never depletes a node)")
	assert_eq(_waves[0], [[_nodes[0]], [_nodes[1]], [_nodes[2]], [_nodes[3]], [_nodes[4]]],
			"BFS from the core over a straight chain: one node per layer, core first")


func test_deallocation_order_unchanged_core_still_last_and_everything_stripped() -> void:
	_entity.stat_board.health.set_current(1.0)
	_nodes[0].take_damage(10000.0, null)

	assert_eq(_owned_count(), 0, "every owned node, including the core, ends up deallocated")
	assert_eq(_dealloc_order.size(), 5, "all 5 nodes force-deallocated")
	assert_eq(_dealloc_order[_dealloc_order.size() - 1], _nodes[0],
			"the mechanical strip order is unchanged by the wave: core still goes LAST")


# ── Scenario 2 (#257): node cascade wave, then a separate entity-death wave ──

func test_scenario_2_node_cascade_wave_then_entity_death_wave_chain_in_order() -> void:
	# Depleting N3 (d) islands N4 (e) -> a 2-node forced-dealloc cascade with its
	# own wave. dealloc_damage chip (1.0/node x 2 nodes) exactly drains health
	# from 2.0 to 0.0, killing the entity mid-cascade -> a second, separate wave
	# over the remaining owned set {a, b, c}.
	_entity.stat_board.dealloc_damage.base_value = 1.0
	_entity.stat_board.health.set_current(2.0)

	_nodes[3].take_damage(10000.0, null)

	assert_true(_entity.is_dead, "the chip damage from the d/e cascade should kill the entity")
	assert_eq(_waves.size(), 2, "the node cascade's own wave, then a separate entity-death wave")
	assert_eq(_waves[0], [[_nodes[3]], [_nodes[4]]], "wave 1: d -> e, BFS from the impact node d")
	assert_eq(_waves[1], [[_nodes[0]], [_nodes[1]], [_nodes[2]]],
			"wave 2: core-outward over what's left after d/e were already stripped")
	assert_eq(_owned_count(), 0, "the full board is still stripped by the end")


# ── Disconnected owned island (#837 acceptance #5) ───────────────────────────

func test_disconnected_owned_island_still_deallocates_and_lands_in_a_final_layer() -> void:
	var island := _SKILL_NODE_SCENE.instantiate() as SkillNode
	island.name = "Island"
	_graph.skill_nodes_container.add_child(island)  # no edges at all -> unreachable via the induced subgraph
	_alloc.force_allocate(_entity, island)

	_entity.stat_board.health.set_current(1.0)
	_nodes[0].take_damage(10000.0, null)

	assert_eq(_waves.size(), 1)
	var layers: Array = _waves[0]
	assert_eq(layers.size(), 6, "5 chain layers + one extra layer for the disconnected island")
	var last_layer: Array = layers[layers.size() - 1]
	assert_true(last_layer.has(island), "the island parks on the final layer rather than being dropped")
	assert_eq(_owned_count(), 0, "the island is still deallocated along with the rest of the board")
