extends GutTest
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## [CorruptionStatus]: damage only on a topple — [method StatusDef._on_burst]
## deals `topples × T × damage_per_power` of the node's MAX hp, unmitigated
## `DamageInstance.Type.TRUE`; a tick deals nothing and nothing is projected.
## Same fixture and kill / cascade path as `test_poison_status.gd`.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _AUTHORED: CorruptionStatus = preload("res://effects/status/corruption.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Corrupted"
	# Flat board: formula test arranges its own stat inputs, tuned CON must not ride in.
	_entity.stat_board = TestBoards.flat_entity_board()
	_graph.add_child(_entity)

	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = "N0"
	_graph.skill_nodes_container.add_child(sn)
	_nodes = [sn]
	await get_tree().process_frame

	_alloc.force_allocate(_entity, _nodes[0])
	_entity.core_location = _nodes[0]


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


func _combat() -> NodeCombat:
	return _nodes[0].get_combat()


## Hand-built at the authored knob (uncapped), so a retune of the `.tres`
## moves every expectation with it.
func _def(per_power: float = _AUTHORED.damage_per_power) -> CorruptionStatus:
	var d := CorruptionStatus.new()
	d.id = &"corruption"
	d.display_name = "Corruption"
	d.tags = [&"debuff", &"dot"]
	d.reapply = StatusDef.Reapply.ACCUMULATE
	d.power_max = 0.0
	d.decay = FractionDecay.new(0.5)
	d.damage_per_power = per_power
	return d


func _set_max_hp(hp: float) -> void:
	# node_health's cap is derived from the OWNER's board, read live on every
	# cap read — drive the entity's baseline, then fill the node's pool.
	_entity.stat_board.get_stat(&"node_health").base_value = hp
	_nodes[0].get_max_hp()
	(_nodes[0].node_board.get_stat(&"node_health") as PoolStat).set_current(hp)


# ── Acceptance 1: burst = topples × T × damage_per_power of max hp ──────────

func test_burst_deals_topples_times_threshold_of_max_hp() -> void:
	_set_max_hp(2000.0)
	var d := _def(0.01)
	d._on_burst(_combat(), 2, 7)
	assert_almost_eq(_nodes[0].get_current_hp(), 2000.0 - 2.0 * 7.0 * d.damage_per_power * 2000.0,
			0.001, "2 topples at T 7: 2 × 7 × X of max hp")


func test_a_tick_deals_nothing() -> void:
	_set_max_hp(2000.0)
	_combat().apply_status(_def(), 10.0)
	_combat().tick_statuses()
	assert_almost_eq(_nodes[0].get_current_hp(), 2000.0, 0.001, "corruption only hurts on a topple")


func test_uncapped_and_accumulates() -> void:
	_combat().apply_status(_def(), 40.0)
	_combat().apply_status(_def(), 40.0)
	assert_almost_eq(_combat().get_status_power(&"corruption"), 80.0, 0.001, "no cap, stacks add")


# ── Acceptance 2: TRUE-typed — armor and a negative floor change nothing ─────

func test_armor_and_damage_floor_change_nothing() -> void:
	_set_max_hp(2000.0)
	_entity.stat_board.get_stat(&"armor").base_value = 100.0
	_entity.stat_board.get_stat(&"min_damage_taken").base_value = -5.0
	assert_almost_eq(_nodes[0].get_combat().get_local_value(&"armor"), 100.0, 0.001, "armor arranged")
	_def()._on_burst(_combat(), 1, 10)
	assert_almost_eq(_nodes[0].get_current_hp(), 2000.0 - 10.0 * _AUTHORED.damage_per_power * 2000.0, 0.001,
			"10 × X of max lands whole: TRUE bypasses armor 100 and the -5 floor alike")


# ── projections: nothing ticks ───────────────────────────────────────────────

func test_projections_are_zero() -> void:
	_set_max_hp(2000.0)
	_combat().apply_status(_def(), 10.0)
	assert_almost_eq(_combat().projected_status_damage(), 0.0, 0.0001, "no tick to project")
	assert_almost_eq(_def().next_tick_damage(_combat(), 10.0), 0.0, 0.0001, "no next tick")


# ── Acceptance 3: a lethal burst kills, cascades and clears ───────────────────

func test_lethal_burst_kills_islands_and_clears_statuses() -> void:
	# core(N0) - N1 - N2, N1 a cut vertex: killing N1 islands N2 too. N2 is
	# corrupted as well so its status must vanish mid cascade without erroring.
	var n1 := _SKILL_NODE_SCENE.instantiate() as SkillNode
	n1.name = "N1"
	_graph.skill_nodes_container.add_child(n1)
	var n2 := _SKILL_NODE_SCENE.instantiate() as SkillNode
	n2.name = "N2"
	_graph.skill_nodes_container.add_child(n2)
	_nodes.append(n1)
	_nodes.append(n2)
	await get_tree().process_frame
	_add_edge(_nodes[0], n1)
	_add_edge(n1, n2)
	_alloc.force_allocate(_entity, n1)
	_alloc.force_allocate(_entity, n2)

	var battle := BattleSystem.new()
	battle.allocation_system = _alloc
	battle.graph = _graph
	add_child_autofree(battle)

	var layers_seen: Array = []
	battle.cascade_started.connect(func(layers: Array, _defender: Entity) -> void:
		layers_seen.append(layers))

	# 1.0 of max hp per unit of T, one topple at T 5 = 500% of max hp: lethal.
	n1.get_combat().apply_status(_def(1.0), 5.0)
	var mild := _def(0.0)
	mild.id = &"corruption_mild"
	n2.get_combat().apply_status(mild, 1.0)

	_def(1.0)._on_burst(n1.get_combat(), 1, 5)

	assert_eq(layers_seen.size(), 1, "cascade_started fired once")
	assert_null(n1.owned_by, "N1 (impact) is unowned")
	assert_null(n2.owned_by, "N2 (islanded) is unowned")
	assert_almost_eq(n1.get_combat().get_status_power(&"corruption"), 0.0, 0.001,
			"the dead node carries no statuses afterwards")
	assert_almost_eq(n2.get_combat().get_status_power(&"corruption_mild"), 0.0, 0.001,
			"the islanded node carries no statuses afterwards")


# ── Acceptance 4: the authored def loads (values are the owner's knobs) ──────

func test_authored_corruption_loads_with_the_model_shape() -> void:
	var c := load("res://effects/status/corruption.tres") as CorruptionStatus
	assert_not_null(c, "corruption.tres is a CorruptionStatus")
	if c == null:
		return
	assert_eq(c.id, &"corruption")
	assert_true(&"debuff" in c.tags, "tagged as a debuff")
	assert_true(&"dot" in c.tags, "tagged as a dot")
	assert_eq(c.stacks_stat_id(), &"corruption_stacks_per_hit")
	assert_eq(c.resistance_stat_id(), &"corruption_resistance")
	assert_true(c.power_max <= 0.0, "uncapped")
	# No decay for now (owner, 2026-10-01; interim until #1203).
	assert_null(c.decay, "corruption does not decay")
	assert_gt(c.display_max, 0.0, "an uncapped def authors its display anchor")
	assert_eq(c.reapply, StatusDef.Reapply.ACCUMULATE)
	assert_gt(c.damage_per_power, 0.0, "deals something per stack")
	assert_false(c.display_name.is_empty(), "display identity lives on the .tres")
	assert_ne(c.tint, Color.WHITE, "authored tint")
