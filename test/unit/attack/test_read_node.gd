extends GutTest

## The per-hit read node: which attacker-side node a hit reads its local stats
## from — the firing leaf (ranged), the node a contacting blade vertex was
## copied from (melee), the cast source on every hop (magic). It sits beside
## [member HitInstance.origin], which stays the VFX spawn point, and it never
## rides the wire.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")
const _POISON_DEF: StatusDef = preload("res://effects/status/poison.tres")


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


# ── 1. Ranged ───────────────────────────────────────────────────────────────

func test_a_resolved_volleys_hits_read_their_firing_leaf() -> void:
	var ctx: Dictionary = await _build()
	var outcome := _ranged_plan(ctx).resolve()
	assert_gt(outcome.hits.size(), 0, "the fixture volley must resolve hits")
	for hit in outcome.hits:
		assert_eq(hit.read_node, ctx.nodes.leaf, "an arrow reads its firing leaf")
		assert_eq(hit.read_node, hit.origin, "ranged: read node == origin")


func test_a_typed_arrows_riders_carry_its_read_node() -> void:
	var ctx: Dictionary = await _build()
	var rider := ApplyStatusEffect.new()
	rider.def = _POISON_DEF
	var type := AmmoType.new()
	type.id = &"read_node_rider"
	type.damage_scale = 1.0
	type.on_hit_effects = [rider] as Array[OnHitEffect]
	var hit := RangedDamageFormula.compute(ctx.attacker, ctx.nodes.leaf, ctx.nodes.target, type)
	var riders := RangedDamageFormula.riders_for(hit)
	assert_eq(hit.read_node, ctx.nodes.leaf, "the arrow reads its firing leaf")
	assert_eq(riders.size(), 1, "one authored rider, one emitted status")
	for r in riders:
		assert_eq(r.read_node, ctx.nodes.leaf, "a rider reads its arrow's leaf")
		assert_eq(r.read_node, r.origin, "ranged rider: read node == origin")


# ── 2. Melee ────────────────────────────────────────────────────────────────

func test_a_blade_contact_reads_the_vertex_node_while_origin_stays_the_pivot() -> void:
	var ctx: Dictionary = await _build()
	var outcome := _melee_plan(ctx).resolve()
	var from_leaf := 0
	for hit in outcome.hits:
		if not (hit is DamageInstance):
			continue
		assert_eq(hit.origin, ctx.nodes.core, "melee origin stays the pivot")
		assert_true(hit.read_node == ctx.nodes.core or hit.read_node == ctx.nodes.leaf,
				"a contact reads one of the blade's own nodes, got %s" % hit.read_node)
		if hit.read_node == ctx.nodes.leaf:
			from_leaf += 1
	assert_gt(from_leaf, 0, "the leaf vertex's contact on the target must read the leaf")


func test_the_blade_state_carries_one_vertex_node_per_particle() -> void:
	var ctx: Dictionary = await _build()
	var state := _melee_plan(ctx).build_blade_state()
	assert_eq(state.vertex_node.size(), state.positions.size(), "one entry per particle")
	assert_true(state.vertex_node.has(ctx.nodes.core), "the pivot is a vertex node")
	assert_true(state.vertex_node.has(ctx.nodes.leaf), "the copied node keeps its reference")


# ── 3. Magic ────────────────────────────────────────────────────────────────

func test_every_hop_reads_the_cast_source_while_origin_is_the_predecessor() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2])
	helper.assign_owner(graph, atk, [0])
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.max_reducer(),
			{max_hops = 2})
	var status := ApplyStatusEffect.new()
	status.def = _POISON_DEF
	var on_hits: Array[OnHitEffect] = [DamageEffect.new(), HealEffect.new(), status]
	var spell := helper.make_spell(config, on_hits, 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	var hop2 := 0
	for hit in outcome.hits:
		assert_eq(hit.read_node, n[0], "every spell hit reads the cast source")
		if hit.target == n[2]:
			hop2 += 1
			assert_eq(hit.origin, n[1], "hop 2's origin is hop 1's node")
	assert_eq(hop2, 3, "hop 2 lands damage, heal and status")


# ── 4. Off the wire ─────────────────────────────────────────────────────────

func test_a_record_round_trip_leaves_read_node_null() -> void:
	var ctx: Dictionary = await _build()
	var outcome := _ranged_plan(ctx).resolve()
	assert_not_null(outcome.hits[0].read_node, "precondition: the resolve stamped it")
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, ctx.graph)))
	var rebuilt := AttackRecord.rebuild(wired, ctx.graph)
	assert_gt(rebuilt.hits.size(), 0, "the record must rebuild hits")
	for hit in rebuilt.hits:
		assert_null(hit.read_node, "read_node never rides the wire")
