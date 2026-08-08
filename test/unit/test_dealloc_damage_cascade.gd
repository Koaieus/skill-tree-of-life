extends GutTest
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## Forced-dealloc cascade chip damage (#59). `BattleSystem._on_node_depleted`
## deducts `dealloc_damage` HP off the defender's `health` pool per cascaded
## node, bypassing `Mitigation.apply` — see `.claude/rules/stats-system.md`
## "Forced-dealloc damage". Exercised via the realistic bus path
## (`SkillNode.take_damage` → `Events.skill_node_depleted`), same pattern as
## `test_entity_death.gd`, so the cascade snapshot + BFS layering run for real.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _battle: BattleSystem
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
	# Line core(N0) – N1 – N2. N1 is a cut vertex: depleting it islands N2.
	_add_edge(_nodes[0], _nodes[1])
	_add_edge(_nodes[1], _nodes[2])

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

	await get_tree().process_frame  # entity._ready: navigator wiring

	for n in _nodes:
		_alloc.force_allocate(_entity, n)
	_entity.core_location = _nodes[0]

	# Headroom so health chip never crosses 0 mid-test (death is covered by
	# test_entity_death.gd, not here).
	_entity.stat_board.health.base_value = 100.0
	_entity.stat_board.health.set_current(100.0)


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


func _wounded() -> int:
	return _entity.stat_board.skill_points.wounded


# ── Per-cascade-node deduction ───────────────────────────────────────────────

func test_leaf_depletion_deducts_one_node_worth() -> void:
	# N2 is a leaf: depleting it islands nobody, so the cascade is just [N2].
	_entity.stat_board.dealloc_damage.base_value = 2.0
	var before := _entity.stat_board.health.current
	_nodes[2].take_damage(10000.0, null)
	assert_almost_eq(before - _entity.stat_board.health.current, 2.0, 0.001)


func test_cut_vertex_depletion_deducts_per_cascaded_node() -> void:
	# N1 is a cut vertex: depleting it islands N2 too → 2-node cascade.
	_entity.stat_board.dealloc_damage.base_value = 2.0
	var before := _entity.stat_board.health.current
	_nodes[1].take_damage(10000.0, null)
	assert_almost_eq(before - _entity.stat_board.health.current, 4.0, 0.001,
			"2 cascaded nodes x 2.0 dealloc_damage")


# ── Bypasses Mitigation.apply ────────────────────────────────────────────────

func test_chip_damage_ignores_armor() -> void:
	_entity.stat_board.dealloc_damage.base_value = 2.0
	_entity.stat_board.armor.base_value = 50.0  # would floor a Mitigation-routed hit
	var before := _entity.stat_board.health.current
	_nodes[1].take_damage(10000.0, null)  # cascade: N1 + N2
	assert_almost_eq(before - _entity.stat_board.health.current, 4.0, 0.001,
			"armor must not reduce dealloc-damage chip")


# ── Fallback for boards missing the stat ─────────────────────────────────────

func test_missing_dealloc_damage_stat_falls_back_to_one() -> void:
	_entity.stat_board.dealloc_damage = null
	var before := _entity.stat_board.health.current
	_nodes[1].take_damage(10000.0, null)  # cascade: N1 + N2
	assert_almost_eq(before - _entity.stat_board.health.current, 2.0, 0.001,
			"2 cascaded nodes x 1.0 fallback")


# ── hp_per_node <= 0 short-circuits ──────────────────────────────────────────

func test_zero_dealloc_damage_deducts_no_health() -> void:
	_entity.stat_board.dealloc_damage.base_value = 0.0
	var before := _entity.stat_board.health.current
	_nodes[1].take_damage(10000.0, null)
	assert_almost_eq(_entity.stat_board.health.current, before, 0.001,
			"zero dealloc_damage should not touch health at all")


func test_negative_dealloc_damage_deducts_no_health() -> void:
	_entity.stat_board.dealloc_damage.base_value = -5.0
	var before := _entity.stat_board.health.current
	_nodes[1].take_damage(10000.0, null)
	assert_almost_eq(_entity.stat_board.health.current, before, 0.001,
			"negative dealloc_damage should not heal or damage health")


# ── Wound-SP + HP chip decoupling ────────────────────────────────────────────

func test_wounding_still_happens_when_health_is_null() -> void:
	_entity.stat_board.health = null
	_nodes[1].take_damage(10000.0, null)  # cascade: N1 + N2, must not crash
	assert_eq(_wounded(), 2, "SP wounding is independent of the health pool")


func test_health_chip_still_happens_when_skill_points_is_null() -> void:
	_entity.stat_board.dealloc_damage.base_value = 2.0
	_entity.stat_board.skill_points = null
	var before := _entity.stat_board.health.current
	_nodes[1].take_damage(10000.0, null)  # cascade: N1 + N2, must not crash
	assert_almost_eq(before - _entity.stat_board.health.current, 4.0, 0.001,
			"health chip is independent of the skill_points pool")


func test_cascade_always_wounds_one_sp_per_cascaded_node() -> void:
	_nodes[1].take_damage(10000.0, null)  # cascade: N1 + N2
	assert_eq(_wounded(), 2, "wound(1) fires once per cascaded node regardless of hp_per_node")
