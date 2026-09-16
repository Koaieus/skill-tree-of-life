extends GutTest
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## [PoisonStatus] (#874, hub #868 D3/D5/D6): unmitigated `DamageInstance.Type.TRUE`
## damage on `_on_tick`, flat or `%`-of-max-hp per [member PoisonStatus.basis],
## scaled by the tick's PRE-decay power. Can kill through the same
## `notify_depleted` → `BattleSystem._on_node_depleted` derive-cascade path a
## bare `take_damage` call reaches (#870) — the amendments' re-entrancy
## gotcha (poisoning an about-to-be-islanded node too) is exercised in the
## kill test below.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

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
	_entity.display_name = "Poisoned"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
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


func _def(basis: HitInstance.AmountBasis, per_power: float, power_max: float = 5.0,
		decay: float = 1.0) -> PoisonStatus:
	var d := PoisonStatus.new()
	d.id = &"poison"
	d.display_name = "Poison"
	d.tags = [&"debuff"]
	d.reapply = StatusDef.Reapply.ACCUMULATE
	d.power_max = power_max
	d.decay_per_tick = decay
	d.basis = basis
	d.damage_per_power = per_power
	return d


# ── Acceptance list (hub #868 issue #874) ────────────────────────────────────

func _set_max_hp(hp: float) -> void:
	# node_health's cap is derived from the OWNER's board (`NodeCombat._node_health_base`,
	# read live on every cap read) — the node's own board only holds `.current`
	# fill once minted, so drive the entity's baseline, not the node board.
	_entity.stat_board.get_stat(&"node_health").base_value = hp
	_nodes[0].get_max_hp()  # materialises the node's node_health pool
	(_nodes[0].node_board.get_stat(&"node_health") as PoolStat).set_current(hp)


func test_flat_ticks_deal_power_times_damage_per_power_and_decay() -> void:
	# Hand-built node, max hp 20, FLAT damage_per_power 2, power 3:
	# tick -> hp 14, power 2; tick -> hp 10, power 1; tick -> hp 8, removed.
	# Armor is left at its default and never touched — TRUE bypasses it
	# entirely, so there is nothing to set for that half of the acceptance line.
	_set_max_hp(20.0)
	var d := _def(HitInstance.AmountBasis.FLAT, 2.0)
	_combat().apply_status(d, 3.0)

	_combat().tick_statuses()
	assert_almost_eq(_nodes[0].get_current_hp(), 14.0, 0.001, "3 power x 2 = 6 damage")
	assert_almost_eq(_combat().get_status_power(&"poison"), 2.0, 0.001, "decays by 1")

	_combat().tick_statuses()
	assert_almost_eq(_nodes[0].get_current_hp(), 10.0, 0.001, "2 power x 2 = 4 damage")

	_combat().tick_statuses()
	assert_almost_eq(_nodes[0].get_current_hp(), 8.0, 0.001, "1 power x 2 = 2 damage")
	assert_almost_eq(_combat().get_status_power(&"poison"), 0.0, 0.001, "removed at 0")


func test_percent_max_scales_by_node_max_hp() -> void:
	_set_max_hp(20.0)
	var d := _def(HitInstance.AmountBasis.PERCENT_MAX, 0.1)
	_combat().apply_status(d, 2.0)

	_combat().tick_statuses()
	assert_almost_eq(_nodes[0].get_current_hp(), 16.0, 0.001,
			"2 power x 0.1 x 20 max hp = 4 damage")


func test_accumulate_stacks_and_clamps_at_power_max() -> void:
	var d := _def(HitInstance.AmountBasis.FLAT, 1.0, 5.0)
	_combat().apply_status(d, 3.0)
	_combat().apply_status(d, 3.0)
	assert_almost_eq(_combat().get_status_power(&"poison"), 5.0, 0.001, "3 + 3 clamps at power_max 5")


func test_poisoned_node_does_not_regen_the_same_upkeep() -> void:
	_set_max_hp(20.0)
	var d := _def(HitInstance.AmountBasis.FLAT, 1.0)
	_combat().apply_status(d, 1.0)

	_combat().tick_statuses()  # hub D4: fires before apply_turn_regen this same upkeep beat
	var after_tick := _nodes[0].get_current_hp()
	_nodes[0].apply_turn_regen()
	assert_almost_eq(_nodes[0].get_current_hp(), after_tick, 0.001,
			"damaged-this-upkeep flag suppresses the tick's own regen")

	_nodes[0].apply_turn_regen()
	assert_gt(_nodes[0].get_current_hp(), after_tick, "next upkeep, flag cleared, regen fires")


# ── Kill + re-entrancy (hub amendments 2026-09-14) ───────────────────────────

func test_lethal_tick_kills_islands_and_clears_statuses() -> void:
	# core(N0) - N1 - N2, N1 a cut vertex: killing N1 by poison islands N2 too.
	# Poisoning N2 as well exercises the amendments' re-entrancy gotcha — its
	# status must vanish mid cascade without erroring.
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

	# Grossly lethal — the node's exact max hp doesn't matter, only that one
	# tick overkills it (acceptance's "power 5 on a 5-hp node").
	var lethal := _def(HitInstance.AmountBasis.FLAT, 100000.0)
	n1.get_combat().apply_status(lethal, 5.0)
	var mild := _def(HitInstance.AmountBasis.FLAT, 0.0)
	mild.id = &"poison_mild"
	n2.get_combat().apply_status(mild, 1.0)

	n1.get_combat().tick_statuses()

	assert_eq(layers_seen.size(), 1, "cascade_started fired once")
	assert_null(n1.owned_by, "N1 (impact) is unowned")
	assert_null(n2.owned_by, "N2 (islanded) is unowned")
	assert_almost_eq(n1.get_combat().get_status_power(&"poison"), 0.0, 0.001,
			"the dead node carries no statuses afterwards")
	assert_almost_eq(n2.get_combat().get_status_power(&"poison_mild"), 0.0, 0.001,
			"the islanded node carries no statuses afterwards")


# ── Authored content loads and is wired (values are the owner's knobs) ──────

func test_authored_poison_and_venom_load_and_are_in_the_debug_book() -> void:
	var poison := load("res://effects/status/poison.tres") as PoisonStatus
	assert_not_null(poison, "poison.tres is a PoisonStatus")
	if poison == null:
		return
	assert_eq(poison.id, &"poison")
	assert_true(&"debuff" in poison.tags, "tagged as a debuff")
	assert_gt(poison.cure_per_hp, 0.0, "healable per hub D7/cure_per_hp amendment")

	var venom := load("res://attack/spell/defs/venom.tres") as SpellDef
	assert_not_null(venom, "venom.tres is a SpellDef")
	if venom == null:
		return
	var applier: ApplyStatusEffect = null
	var has_damage := false
	for fx in venom.on_hit_effects:
		if fx is ApplyStatusEffect:
			applier = fx
		elif fx is DamageEffect:
			has_damage = true
	assert_true(has_damage, "venom also deals a little damage")
	assert_not_null(applier, "venom composes an ApplyStatusEffect")
	if applier != null:
		assert_eq(applier.def, poison, "…that applies the authored Poison def")
		assert_gt(applier.power, 0.0)

	var book := load("res://entity/spellbook_debug.tres") as SpellBook
	assert_true(venom in book.spells, "venom is in the debug spellbook")
