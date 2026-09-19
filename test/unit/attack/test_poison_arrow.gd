extends GutTest

## #495 — what a typed arrow does on hit. A poison arrow (`attack/ammo/types/
## poison.tres`) lands for `damage_scale` × the loosed amount and leaves a
## [PoisonStatus] on the node via a [StatusInstance] emitted alongside the
## [DamageInstance] for the same landing; a volley's many arrows on one node
## re-apply under the def's `ACCUMULATE` rule, capped by `power_max`. A base
## arrow leaves nothing; a gated (dud) arrow leaves nothing; and the record
## carries the status hits to a peer unchanged.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")
const _POISON_ARROW: AmmoType = preload("res://attack/ammo/types/poison.tres")
const _BASE_ARROW: AmmoType = preload("res://attack/ammo/types/base.tres")
const _POISON_DEF: StatusDef = preload("res://effects/status/poison.tres")

const _PEER_ORIGIN := Vector2(100000, 100000)
## Even, so `× 0.5` is exact whatever the landing rounds to.
const _BASE_DAMAGE := 8.0


func _set_local(node: SkillNode, stat_id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


## Attacker owns core–leaf, defender owns target–neighbour; the leaf reaches
## the target with `shots` shots and a modest `ranged_damage` so the target
## SURVIVES a volley (a killed node clears its statuses — nothing to assert).
func _build(origin: Vector2 = Vector2.ZERO, shots: float = 1.0) -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var nodes: Dictionary = {}
	for entry in [["core", Vector2(0, 0)], ["leaf", Vector2(150, 0)],
			["target", Vector2(150, 0)], ["neighbour", Vector2(300, 0)]]:
		var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		node.name = str(entry[0])
		graph.add_skill_node(node)
		node.global_position = origin + (entry[1] as Vector2)
		nodes[entry[0]] = node
	graph.add_edge(nodes.core, nodes.leaf)
	graph.add_edge(nodes.leaf, nodes.target)
	graph.add_edge(nodes.target, nodes.neighbour)

	var attacker := Entity.new()
	attacker.display_name = "Attacker"
	attacker.faction = _PLAYER_FACTION
	attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	attacker.stat_board.arrows.add(AmmoTypeRoster.BASE_ID, 40)
	attacker.stat_board.arrows.add(&"poison", 40)
	attacker.stat_board.action_points.base_value = 4.0
	attacker.stat_board.action_points.current = 4.0
	graph.entities_container.add_child(attacker)

	var defender := Entity.new()
	defender.display_name = "Defender"
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
	_set_local(nodes.leaf, &"ranged_damage", _BASE_DAMAGE)
	_set_local(nodes.leaf, &"max_shots_per_leaf", shots)
	# Statuses ride HP; make sure a handful of half-strength arrows cannot kill.
	_set_local(nodes.target, &"node_combat_health", 1000.0)
	nodes.target.get_combat().refill(true)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.current_entity = attacker

	var bs := BattleSystem.new()
	bs.turn_manager = tm
	bs.allocation_system = alloc
	bs.graph = graph
	bs.instant_mutation = true
	add_child_autofree(bs)

	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	return {"graph": graph, "bs": bs, "attacker": attacker,
			"defender": defender, "nodes": nodes}


func _poison_power(node: SkillNode) -> float:
	return node.get_combat().get_status_power(&"poison")


func _arm(ctx: Dictionary, counts: Dictionary) -> RangedAttackPlan:
	var bs: BattleSystem = ctx.bs
	bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	var plan := bs.attack_plan as RangedAttackPlan
	plan._on_node_left_clicked(ctx.nodes.target)
	plan.ammo_counts = counts
	return plan


# ── The formula: one arrow ──────────────────────────────────────────────────

func test_a_poison_arrow_is_loosed_at_damage_scale_times_the_base_read() -> void:
	var ctx: Dictionary = await _build()
	var hit := RangedDamageFormula.compute(ctx.attacker, ctx.nodes.leaf, ctx.nodes.target, _POISON_ARROW)
	assert_almost_eq(hit.amount, _BASE_DAMAGE * _POISON_ARROW.damage_scale, 0.001)
	assert_lt(_POISON_ARROW.damage_scale, 1.0,
			"owner 2026-09-18: 'reduced raw damage + added poison status stacks'")


func test_a_poison_arrows_status_lands_with_power_one_beside_its_damage() -> void:
	var ctx: Dictionary = await _build()
	var target: SkillNode = ctx.nodes.target
	var hit := RangedDamageFormula.compute(ctx.attacker, ctx.nodes.leaf, target, _POISON_ARROW)
	var status := RangedDamageFormula.status_for(hit)
	assert_not_null(status, "a typed arrow with a status_def emits a StatusInstance")
	assert_eq(status.def, _POISON_DEF)
	assert_eq(status.target, target)
	assert_eq(status.origin, ctx.nodes.leaf)
	assert_eq(status.attacker, ctx.attacker)
	var hp_before := target.get_current_hp()
	var world := CombatWorld.live()
	hit.land_on(target.get_combat(), world)
	status.land_on(target.get_combat(), world)
	assert_almost_eq(hp_before - target.get_current_hp(), _BASE_DAMAGE * 0.5, 0.001,
			"half the base arrow's damage")
	assert_almost_eq(_poison_power(target), 1.0, 0.001, "one arrow, power 1")


func test_a_base_arrow_emits_no_status() -> void:
	var ctx: Dictionary = await _build()
	var hit := RangedDamageFormula.compute(ctx.attacker, ctx.nodes.leaf, ctx.nodes.target, _BASE_ARROW)
	assert_null(RangedDamageFormula.status_for(hit))
	assert_almost_eq(hit.amount, _BASE_DAMAGE, 0.001, "base arrow: full damage")
	var untyped := RangedDamageFormula.compute(ctx.attacker, ctx.nodes.leaf, ctx.nodes.target)
	assert_null(RangedDamageFormula.status_for(untyped), "no ammo type at all: nothing to apply")


func test_a_gated_poison_arrow_applies_no_status() -> void:
	var ctx: Dictionary = await _build()
	var target: SkillNode = ctx.nodes.target
	var hit := RangedDamageFormula.compute(ctx.attacker, ctx.nodes.leaf, target, _POISON_ARROW)
	var status := RangedDamageFormula.status_for(hit)
	# The target fell to an earlier arrow's kill cascade before this one lands.
	target.owned_by = null
	var world := CombatWorld.live()
	hit.land_on(target.get_combat(), world)
	status.land_on(target.get_combat(), world)
	assert_true(hit.gated)
	assert_true(status.gated, "the status shares its arrow's dud gate")
	assert_almost_eq(_poison_power(target), 0.0, 0.001, "a dud leaves no status")
	assert_almost_eq(status.effective_amount, 0.0, 0.001)


# ── The volley: many arrows on one node ─────────────────────────────────────

func test_three_poison_arrows_in_one_volley_accumulate_to_power_three() -> void:
	var ctx: Dictionary = await _build(Vector2.ZERO, 3.0)
	var plan := _arm(ctx, {&"poison": 3})
	assert_eq(plan.validate(), [] as Array[String], "the fixture volley must be launchable")
	var outcome := plan.resolve()
	var status_hits := outcome.hits.filter(func(h: HitInstance) -> bool: return h.kind == HitInstance.Kind.STATUS)
	assert_eq(status_hits.size(), 3, "one status hit per poison arrow, alongside the damage hit")
	assert_almost_eq(_poison_power(ctx.nodes.target), 3.0, 0.001,
			"ACCUMULATE: a volley stacks up poison — that is what makes ranged the specialist")


func test_a_volley_past_power_max_is_capped() -> void:
	var ctx: Dictionary = await _build(Vector2.ZERO, 7.0)
	var plan := _arm(ctx, {&"poison": 7})
	assert_eq(plan.validate(), [] as Array[String], "the fixture volley must be launchable")
	plan.resolve()
	assert_almost_eq(_poison_power(ctx.nodes.target), _POISON_DEF.power_max, 0.001)


func test_a_mixed_volley_only_poisons_per_poison_arrow() -> void:
	var ctx: Dictionary = await _build(Vector2.ZERO, 3.0)
	var plan := _arm(ctx, {&"poison": 1, AmmoTypeRoster.BASE_ID: 2})
	assert_eq(plan.validate(), [] as Array[String], "the fixture volley must be launchable")
	plan.resolve()
	assert_almost_eq(_poison_power(ctx.nodes.target), 1.0, 0.001)


# ── The wire ────────────────────────────────────────────────────────────────

func test_the_record_replays_the_same_poison_on_a_peer() -> void:
	var host: Dictionary = await _build(Vector2.ZERO, 3.0)
	var peer: Dictionary = await _build(_PEER_ORIGIN, 3.0)
	_arm(host, {&"poison": 3})
	var bs: BattleSystem = host.bs
	var command := bs.build_launch_command()
	assert_not_null(command, "the fixture plan must be launchable")
	assert_true(bs.prepare_launch_command(command), "the fixture attack must survive validation")
	@warning_ignore("redundant_await")
	await bs.apply_launch_command(command)
	assert_almost_eq(_poison_power(host.nodes.target), 3.0, 0.001, "the authority poisoned its target")
	assert_eq((host.nodes.leaf as SkillNode).shots_fired_this_turn, 3,
			"one shot per ARROW — a status hit must not burn a second shot")

	var back := CommandCodec.from_dict(bytes_to_var(var_to_bytes(command.to_dict())) as Dictionary)
	await (peer.bs as BattleSystem).apply_launch_command(back as LaunchAttackCommand)
	assert_almost_eq(_poison_power(peer.nodes.target), _poison_power(host.nodes.target), 0.001,
			"the rebuilt record reproduces the status hits on a second world")
	assert_almost_eq(peer.nodes.target.get_current_hp(), host.nodes.target.get_current_hp(), 0.001,
			"and the half-strength damage")


func test_a_kill_mid_volley_gates_the_remaining_poison_and_replays_clean() -> void:
	var host: Dictionary = await _build(Vector2.ZERO, 3.0)
	var peer: Dictionary = await _build(_PEER_ORIGIN, 3.0)
	for ctx in [host, peer]:
		# One half-strength arrow kills: arrows 2 and 3 (and their statuses) dud.
		_set_local(ctx.nodes.target, &"node_combat_health", 1.0)
		(ctx.nodes.target as SkillNode).get_combat().refill(true)
	_arm(host, {&"poison": 3})
	var bs: BattleSystem = host.bs
	var command := bs.build_launch_command()
	assert_true(bs.prepare_launch_command(command), "the fixture attack must survive validation")
	@warning_ignore("redundant_await")
	await bs.apply_launch_command(command)
	var kinds: PackedByteArray = command.record[AttackRecord.KEY_HIT_KIND]
	var flags: PackedByteArray = command.record[AttackRecord.KEY_HIT_FLAGS]
	var defs: PackedStringArray = command.record[AttackRecord.KEY_HIT_STATUS_DEF]
	var gated_statuses := 0
	for i in kinds.size():
		if kinds[i] == int(HitInstance.Kind.STATUS):
			assert_eq(defs[i], _POISON_DEF.resource_path, "a status hit crosses as its def path")
			if (flags[i] & AttackRecord.FLAG_GATED) != 0:
				gated_statuses += 1
	assert_eq(gated_statuses, 2, "the two arrows after the kill dud, statuses included")
	var back := CommandCodec.from_dict(bytes_to_var(var_to_bytes(command.to_dict())) as Dictionary)
	await (peer.bs as BattleSystem).apply_launch_command(back as LaunchAttackCommand)
	assert_eq(WorldFingerprint.compute(host.graph), WorldFingerprint.compute(peer.graph))
	assert_almost_eq(_poison_power(peer.nodes.target), _poison_power(host.nodes.target), 0.001)
