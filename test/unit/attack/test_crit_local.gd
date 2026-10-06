extends GutTest

## `crit_chance` is read per hit off the hit's read node
## ([member HitInstance.read_node]): a node-local grant crits that node's hits
## only. With a zero entity board, a node without a grant never draws, so the
## crit stream is unchanged for it.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")


func _set_local(node: SkillNode, stat_id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


## Attacker owns core–leaf, defender owns target–neighbour. The target sits ON
## the leaf so a swing's leaf vertex contacts it at t=0 without depending on
## physics sync timing (the `test_attack_record_replay.gd` trick).
func _build() -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var nodes: Dictionary = {}
	for entry in [["core", Vector2(0, 0)], ["leaf", Vector2(150, 0)],
			["target", Vector2(150, 0)], ["neighbour", Vector2(300, 0)]]:
		var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		node.name = str(entry[0])
		graph.add_skill_node(node)
		node.global_position = entry[1] as Vector2
		nodes[entry[0]] = node
	graph.add_edge(nodes.core, nodes.leaf)
	graph.add_edge(nodes.leaf, nodes.target)
	graph.add_edge(nodes.target, nodes.neighbour)

	var attacker := Entity.new()
	attacker.faction = _PLAYER_FACTION
	attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	attacker.stat_board.arrows.add(AmmoTypeRoster.BASE_ID, 40)
	attacker.stat_board.blade_size.base_value = 2.0
	attacker.stat_board.action_points.base_value = 4.0
	attacker.stat_board.action_points.current = 4.0
	attacker.stat_board.get_stat(&"crit_chance").base_value = 0.0
	graph.entities_container.add_child(attacker)
	var defender := Entity.new()
	defender.faction = _NPC_FACTION
	defender.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(defender)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(attacker, nodes.core)
	alloc.force_allocate(attacker, nodes.leaf)
	attacker.core_location = nodes.core
	alloc.force_allocate(defender, nodes.target)
	alloc.force_allocate(defender, nodes.neighbour)
	defender.core_location = nodes.neighbour
	_set_local(nodes.leaf, &"range", 400.0)
	_set_local(nodes.leaf, &"ranged_damage", 5.0)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.start_turn(attacker)
	var bs := BattleSystem.new()
	bs.turn_manager = tm
	bs.allocation_system = alloc
	bs.graph = graph
	bs.instant_mutation = true
	add_child_autofree(bs)

	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	return {"graph": graph, "bs": bs, "attacker": attacker, "nodes": nodes}


func _ranged_plan(ctx: Dictionary) -> RangedAttackPlan:
	var bs: BattleSystem = ctx.bs
	var plan := bs.new_plan(BattleSystem.AttackMode.RANGED, ctx.attacker) as RangedAttackPlan
	plan.set_target(ctx.nodes.target)
	return plan


func _melee_plan(ctx: Dictionary) -> MeleeAttackPlan:
	var bs: BattleSystem = ctx.bs
	var plan := bs.new_plan(BattleSystem.AttackMode.MELEE, ctx.attacker) as MeleeAttackPlan
	plan.set_pivot(ctx.nodes.core)
	plan.toggle_member(ctx.nodes.leaf)
	return plan



func _grant_crit(node: SkillNode) -> void:
	_set_local(node, &"crit_chance", 1.0)


# ── 1. Ranged ───────────────────────────────────────────────────────────────

func test_a_local_grant_on_a_firing_node_crits_its_arrows_only() -> void:
	var ctx: Dictionary = await _build()
	_grant_crit(ctx.nodes.leaf)
	var outcome := _ranged_plan(ctx).resolve()
	var leaf_hits := 0
	for hit in outcome.hits:
		if hit.read_node == ctx.nodes.leaf:
			leaf_hits += 1
			assert_true(hit.is_crit, "an arrow from the granted leaf crits")
		else:
			assert_false(hit.is_crit, "an arrow from an ungranted node never crits")
	assert_gt(leaf_hits, 0, "the leaf must fire")


func test_an_ungranted_node_does_not_draw_from_the_stream() -> void:
	var ctx: Dictionary = await _build()
	var rng := CritRoll.stream_for(1234)
	var state_before := rng.state
	var hit := RangedDamageFormula.compute(ctx.attacker, ctx.nodes.core, ctx.nodes.target)
	hit.amount = 5.0
	CritRoll.decide(hit, rng)
	assert_eq(rng.state, state_before, "zero crit on the read node: no draw")
	_grant_crit(ctx.nodes.leaf)
	var granted := RangedDamageFormula.compute(ctx.attacker, ctx.nodes.leaf, ctx.nodes.target)
	granted.amount = 5.0
	CritRoll.decide(granted, rng)
	assert_ne(rng.state, state_before, "a granted read node draws")
	assert_true(granted.is_crit)


# ── 2. Melee ────────────────────────────────────────────────────────────────

func test_a_local_grant_on_a_copied_node_crits_its_contacts_not_the_pivots() -> void:
	var ctx: Dictionary = await _build()
	_grant_crit(ctx.nodes.leaf)
	var outcome := _melee_plan(ctx).resolve()
	var leaf_hits := 0
	for hit in outcome.hits:
		if not (hit is DamageInstance) or hit.amount <= 0.0:
			continue
		if hit.read_node == ctx.nodes.leaf:
			leaf_hits += 1
			assert_true(hit.is_crit, "the granted copied node's contact crits")
		else:
			assert_false(hit.is_crit, "a contact read off another node never crits")
	assert_gt(leaf_hits, 0, "the leaf vertex must contact the target")


# ── 3. Magic ────────────────────────────────────────────────────────────────

func _cast(grant_index: int) -> Dictionary:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2]], self)
	var atk := helper.make_entity(graph, "A")
	atk.stat_board.get_stat(&"crit_chance").base_value = 0.0
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2])
	helper.assign_owner(graph, atk, [0])
	var n := graph.get_skill_nodes()
	_grant_crit(n[grant_index])
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.max_reducer(),
			{max_hops = 2})
	var on_hits: Array[OnHitEffect] = [DamageEffect.new()]
	var spell := helper.make_spell(config, on_hits, 10.0)
	return {"n": n, "outcome": SpellResolver.resolve(spell, n[1], n[0], atk, graph)}


func test_a_grant_on_the_cast_source_crits_every_hop() -> void:
	var cast := _cast(0)
	var n: Array = cast.n
	var hop2 := 0
	for hit in (cast.outcome as AttackOutcome).hits:
		if hit is ExertInstance:
			continue
		assert_true(hit.is_crit, "every hop reads the source's grant")
		if hit.target == n[2]:
			hop2 += 1
	assert_gt(hop2, 0, "the cast must reach hop 2")


func test_a_grant_on_the_hop_1_node_crits_nothing() -> void:
	var cast := _cast(1)
	var hits: Array = (cast.outcome as AttackOutcome).hits
	assert_gt(hits.size(), 0)
	for hit in hits:
		assert_false(hit.is_crit, "a hop node is not a read node")
