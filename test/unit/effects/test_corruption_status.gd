extends GutTest
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## [CorruptionStatus] (#964, hub #952): a fraction of the node's MAX hp per
## stack per tick, unmitigated `DamageInstance.Type.TRUE`, halving and
## uncapped. Mirrors `test_poison_status.gd` — same fixture, same kill /
## cascade path — with the series computed from `StatusDef.decayed()`: ten
## stacks halve 10 → 5 → 2.5 → 1.25 and the 0.625 tail is cut before it
## ticks, so four ticks land, not five.

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


## Hand-built at the model's anchor (0.02, halving, uncapped) — the authored
## `.tres` is the owner's to tune, so only the shape tests read it.
func _def(per_power: float = 0.02) -> CorruptionStatus:
	var d := CorruptionStatus.new()
	d.id = &"corruption"
	d.display_name = "Corruption"
	d.tags = [&"debuff", &"dot"]
	d.reapply = StatusDef.Reapply.ACCUMULATE
	d.power_max = 0.0
	d.decay_mode = StatusDef.DecayMode.FRACTION
	d.decay_per_tick = 0.5
	d.damage_per_power = per_power
	return d


func _set_max_hp(hp: float) -> void:
	# node_health's cap is derived from the OWNER's board, read live on every
	# cap read — drive the entity's baseline, then fill the node's pool.
	_entity.stat_board.get_stat(&"node_health").base_value = hp
	_nodes[0].get_max_hp()
	(_nodes[0].node_board.get_stat(&"node_health") as PoolStat).set_current(hp)


# ── Acceptance 1: % of max hp per stack, halving ─────────────────────────────

func test_ten_stacks_on_a_2000_hp_node_deal_the_halving_series() -> void:
	_set_max_hp(2000.0)
	_combat().apply_status(_def(), 10.0)
	var expected := [400.0, 200.0, 100.0, 50.0]
	var hp := 2000.0
	for dmg: float in expected:
		_combat().tick_statuses()
		hp -= dmg
		assert_almost_eq(_nodes[0].get_current_hp(), hp, 0.001, "tick deals %s" % dmg)
	assert_almost_eq(_combat().get_status_power(&"corruption"), 0.0, 0.001,
			"0.625 < 1: cleared on the fourth tick, the tail never lands")
	_combat().tick_statuses()
	assert_almost_eq(_nodes[0].get_current_hp(), 1250.0, 0.001, "nothing left to tick")


func test_ten_stacks_on_a_20_hp_node_deal_four_first() -> void:
	_set_max_hp(20.0)
	_combat().apply_status(_def(), 10.0)
	_combat().tick_statuses()
	assert_almost_eq(_nodes[0].get_current_hp(), 16.0, 0.001, "10 x 0.02 x 20 = 4")


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
	_combat().apply_status(_def(), 10.0)
	_combat().tick_statuses()
	assert_almost_eq(_nodes[0].get_current_hp(), 1600.0, 0.001,
			"400 lands whole: TRUE bypasses armor 100 and the -5 floor alike")


# ── projected_damage (#962 hook for #953's overlay) ──────────────────────────

func test_projected_damage_sums_the_remaining_ticks_against_max_hp() -> void:
	_set_max_hp(2000.0)
	assert_almost_eq(_combat().projected_status_damage(), 0.0, 0.0001, "no statuses")
	_combat().apply_status(_def(), 10.0)
	assert_almost_eq(_combat().projected_status_damage(), 750.0, 0.001,
			"400 + 200 + 100 + 50; the 0.625-stack tail never ticks")
	_combat().tick_statuses()
	assert_almost_eq(_combat().projected_status_damage(), 350.0, 0.001, "shrinks as it ticks")


# ── Acceptance 3: a lethal tick kills, cascades and clears ───────────────────

func test_lethal_tick_kills_islands_and_clears_statuses() -> void:
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

	# 1.0 of max hp per stack at power 5 = 500% of max hp: lethal at any size.
	n1.get_combat().apply_status(_def(1.0), 5.0)
	var mild := _def(0.0)
	mild.id = &"corruption_mild"
	n2.get_combat().apply_status(mild, 1.0)

	n1.get_combat().tick_statuses()

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
	assert_eq(c.potency_stat_id, &"corruption_potency")
	assert_eq(c.resistance_stat_id, &"corruption_resistance")
	assert_true(c.power_max <= 0.0, "uncapped")
	assert_eq(c.decay_mode, StatusDef.DecayMode.FRACTION)
	assert_almost_eq(c.decay_per_tick, 0.5, 0.0001, "halves")
	assert_gt(c.display_max, 0.0, "an uncapped def authors its display anchor")
	assert_eq(c.reapply, StatusDef.Reapply.ACCUMULATE)
	assert_gt(c.damage_per_power, 0.0, "deals something per stack")
	assert_gt(c.cure_per_hp, 0.0, "healable")
	assert_false(c.display_name.is_empty(), "display identity lives on the .tres")
	assert_ne(c.tint, Color.WHITE, "authored tint")
