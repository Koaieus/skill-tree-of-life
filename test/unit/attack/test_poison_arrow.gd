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
const _BASE_ARROW: AmmoType = preload("res://attack/ammo/types/arrow.tres")
const _POISON_DEF: StatusDef = preload("res://effects/status/poison.tres")

const _PEER_ORIGIN := Vector2(100000, 100000)
## Even, so `× 0.5` is exact whatever the landing rounds to — and small, so a
## default-HP (10) target SURVIVES seven half-strength arrows: a killed node
## clears its statuses, leaving nothing to assert.
const _BASE_DAMAGE := 2.0


func _set_local(node: SkillNode, stat_id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


## Attacker owns core–leaf, defender owns target–neighbour; the leaf reaches
## the target with `shots` shots and a modest `ranged_damage`.
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
	# Capacity-clamped (`add` returns what fit): specials first, then base.
	assert_eq(attacker.stat_board.arrows.add(&"poison", 8), 8, "fixture quiver must hold the poison")
	attacker.stat_board.arrows.add(AmmoTypeRoster.BASE_ID, 8)
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

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.adopt_turn(attacker, tm.turns_taken)

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
	plan.handle_left_click(ctx.nodes.target)
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
	var world := CombatWorld.live()
	hit.land_on(target.get_combat(), world)
	status.land_on(target.get_combat(), world)
	assert_false(hit.gated)
	assert_false(status.gated)
	assert_almost_eq(_poison_power(target), 1.0, 0.001, "one arrow, power 1")
	assert_almost_eq(status.effective_amount, 1.0, 0.001, "the power rides the wire field")


func test_damage_scale_applies_before_mitigation() -> void:
	# Acceptance: "lands for round(base × 0.5) AFTER mitigation" — i.e. scale
	# first, then armour: 8 × 0.5 − 1 = 3, not (8 − 1) × 0.5 = 3.5.
	var ctx: Dictionary = await _build()
	var target: SkillNode = ctx.nodes.target
	_set_local(ctx.nodes.leaf, &"ranged_damage", 8.0)
	_set_local(target, &"armor", 1.0)
	var ammo := AmmoType.new()  # hand-built: the owner tunes poison.tres
	ammo.damage_scale = 0.5
	var hit := RangedDamageFormula.compute(ctx.attacker, ctx.nodes.leaf, target, ammo)
	var hp_before := target.get_current_hp()
	hit.land_on(target.get_combat(), CombatWorld.live())
	assert_almost_eq(hp_before - target.get_current_hp(), 3.0, 0.001,
			"scaled by damage_scale, THEN mitigated")


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
	# `resolve()` lands on a throwaway shadow; the assertion wants the live node.
	var outcome := plan.resolve_against(CombatWorld.live())
	var status_hits := outcome.hits.filter(func(h: HitInstance) -> bool: return h.kind == HitInstance.Kind.STATUS)
	assert_eq(status_hits.size(), 3, "one status hit per poison arrow, alongside the damage hit")
	assert_almost_eq(_poison_power(ctx.nodes.target), 3.0, 0.001,
			"ACCUMULATE: a volley stacks up poison — that is what makes ranged the specialist")


func test_a_volley_is_never_capped() -> void:
	# #962: poison stacks are uncapped — a 6-arrow volley lands 6 stacks (per
	# arrow `status_power`, owner-tuned; asserted as a multiple, never a value).
	var ctx: Dictionary = await _build(Vector2.ZERO, 6.0)  # six shots on the leaf
	# Keep the arrows' own damage from killing the target — the stacks are the
	# point, and a kill clears the slice.
	_set_local(ctx.nodes.leaf, &"ranged_damage", 0.1)
	var per_arrow: float = _POISON_ARROW.status_power
	var plan := _arm(ctx, {&"poison": 6})
	assert_eq(plan.validate(), [] as Array[String], "the fixture volley must be launchable")
	plan.resolve_against(CombatWorld.live())
	assert_true(_POISON_DEF.power_max <= 0.0, "the authored def is uncapped")
	assert_almost_eq(_poison_power(ctx.nodes.target), 6.0 * per_arrow, 0.001, "six arrows, six stacks")


func test_a_mixed_volley_only_poisons_per_poison_arrow() -> void:
	var ctx: Dictionary = await _build(Vector2.ZERO, 3.0)
	var plan := _arm(ctx, {&"poison": 1, AmmoTypeRoster.BASE_ID: 2})
	assert_eq(plan.validate(), [] as Array[String], "the fixture volley must be launchable")
	plan.resolve_against(CombatWorld.live())
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
	# Both the leaf and the core reach the target (wave-major, nearest first).
	assert_eq((host.nodes.leaf as SkillNode).shots_fired_this_turn
			+ (host.nodes.core as SkillNode).shots_fired_this_turn, 3,
			"one shot per ARROW — a status hit must not burn a second shot")

	var back := CommandCodec.from_dict(bytes_to_var(var_to_bytes(command.to_dict())) as Dictionary)
	await (peer.bs as BattleSystem).apply_launch_command(back as LaunchAttackCommand)
	assert_almost_eq(_poison_power(peer.nodes.target), _poison_power(host.nodes.target), 0.001,
			"the rebuilt record reproduces the status hits on a second world")
	assert_almost_eq(peer.nodes.target.get_current_hp(), host.nodes.target.get_current_hp(), 0.001,
			"and the half-strength damage")


func test_a_heal_flipped_arrow_still_burns_its_shot_and_its_status_never_does() -> void:
	# A bunker-style target (net `min_damage_taken` < 0) flips the arrow's
	# DamageInstance to Kind.HEAL after mitigation (ADR 0012). "A shot fired
	# is a shot fired" (owner, 2026-09-18): the shot count must not key on
	# `kind` — it skips the status hit by CLASS, never the flipped arrow.
	var ctx: Dictionary = await _build()
	_set_local(ctx.nodes.target, &"armor", 50.0)
	_set_local(ctx.nodes.target, &"min_damage_taken", -5.0)
	_arm(ctx, {&"poison": 1})
	var bs: BattleSystem = ctx.bs
	var command := bs.build_launch_command()
	assert_true(bs.prepare_launch_command(command), "the fixture attack must survive validation")
	@warning_ignore("redundant_await")
	await bs.apply_launch_command(command)
	var kinds: PackedByteArray = command.record[AttackRecord.KEY_HIT_KIND]
	assert_true(kinds.has(int(HitInstance.Kind.HEAL)), "the fixture arrow must actually flip to a heal")
	assert_eq((ctx.nodes.leaf as SkillNode).shots_fired_this_turn
			+ (ctx.nodes.core as SkillNode).shots_fired_this_turn, 1,
			"one arrow, one shot — heal-flipped or not, status hit not counted")


func test_a_kill_mid_volley_gates_the_remaining_poison_and_replays_clean() -> void:
	var host: Dictionary = await _build(Vector2.ZERO, 3.0)
	var peer: Dictionary = await _build(_PEER_ORIGIN, 3.0)
	for ctx in [host, peer]:
		# Down to 1 HP: the first arrow kills, so its own status (poison on a
		# corpse is nothing) and both later arrows with theirs all dud.
		var slice: NodeCombat = (ctx.nodes.target as SkillNode).get_combat()
		slice.take_damage(slice.get_current_hp() - 1.0, null)
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
	assert_eq(gated_statuses, 3, "every status of a volley that killed on arrow one is a dud")
	var back := CommandCodec.from_dict(bytes_to_var(var_to_bytes(command.to_dict())) as Dictionary)
	await (peer.bs as BattleSystem).apply_launch_command(back as LaunchAttackCommand)
	assert_eq(WorldFingerprint.compute(host.graph), WorldFingerprint.compute(peer.graph))
	assert_almost_eq(_poison_power(peer.nodes.target), _poison_power(host.nodes.target), 0.001)


# ── #996: a status on a cracked core falls through to the entity ────────────
#
# The defender's core is `nodes.neighbour` (300 from the leaf, in range).
# `_crack_shot` sizes the arrow to land EXACTLY the core's max HP: the node
# goes to 0 with no overflow, so the `health` pool — and the entity — survive
# and `is_allocated()` (alive) still lets a CLEAR def land.

func _core_of(ctx: Dictionary) -> SkillNode:
	return ctx.nodes.neighbour


func _entity_poison(ctx: Dictionary) -> float:
	return (ctx.defender as Entity).get_combat().get_status_power(&"poison")


func _crack_shot(ctx: Dictionary) -> void:
	_set_local(ctx.nodes.leaf, &"ranged_damage",
			_core_of(ctx).get_max_hp() / _POISON_ARROW.damage_scale)


func _land_poison_arrow(ctx: Dictionary, world: CombatWorld, with_damage: bool = true) -> StatusInstance:
	var core := _core_of(ctx)
	var hit := RangedDamageFormula.compute(ctx.attacker, ctx.nodes.leaf, core, _POISON_ARROW)
	var status := RangedDamageFormula.status_for(hit)
	if with_damage:
		hit.land_on(world.combat_for(core), world)
	status.land_on(world.combat_for(core), world)
	return status


func test_a_poison_arrow_on_a_full_hp_core_lands_on_the_node_not_the_entity() -> void:
	var ctx: Dictionary = await _build()
	_land_poison_arrow(ctx, CombatWorld.live())
	assert_almost_eq(_poison_power(_core_of(ctx)), 1.0, 0.001, "an intact core hosts its own poison")
	assert_eq((ctx.defender as Entity).get_statuses().size(), 0, "the entity has no rows")


func test_a_poison_arrow_that_cracks_the_core_in_the_same_shot_lands_on_the_entity() -> void:
	var ctx: Dictionary = await _build()
	_crack_shot(ctx)
	var status := _land_poison_arrow(ctx, CombatWorld.live())
	assert_almost_eq(_core_of(ctx).get_current_hp(), 0.0, 0.001, "sanity: the arrow cracked the core")
	assert_false((ctx.defender as Entity).is_dead, "sanity: no overflow, the entity lives")
	assert_almost_eq(_entity_poison(ctx), 1.0, 0.001, "the status fell through to the entity")
	assert_almost_eq(_poison_power(_core_of(ctx)), 0.0, 0.001, "and not onto the cracked node")
	assert_eq(status.host_kind, StatusInstance.HostKind.ENTITY, "the landed host is a resolved fact")


func test_a_status_only_hit_on_an_already_cracked_core_lands_on_the_entity() -> void:
	var ctx: Dictionary = await _build()
	_core_of(ctx).restore_current_hp(0.0)
	_land_poison_arrow(ctx, CombatWorld.live(), false)
	assert_almost_eq(_entity_poison(ctx), 1.0, 0.001, "zero damage, cracked core: still the entity's")
	assert_almost_eq(_poison_power(_core_of(ctx)), 0.0, 0.001)


func test_a_shadow_fall_through_never_writes_the_live_entity_until_the_record_replays() -> void:
	var ctx: Dictionary = await _build()
	_crack_shot(ctx)
	_arm(ctx, {&"poison": 1})
	(ctx.bs.attack_plan as RangedAttackPlan).handle_left_click(_core_of(ctx))
	var bs: BattleSystem = ctx.bs
	var command := bs.build_launch_command()
	assert_not_null(command, "the fixture plan must be launchable")
	# prepare resolves on a throwaway shadow — the fall-through happens there.
	assert_true(bs.prepare_launch_command(command), "the fixture attack must survive validation")
	assert_almost_eq(_entity_poison(ctx), 0.0, 0.001, "a shadow resolve leaves the live entity clean")
	assert_almost_eq(_core_of(ctx).get_current_hp(), _core_of(ctx).get_max_hp(), 0.001,
			"and the live core untouched")
	@warning_ignore("redundant_await")
	await bs.apply_launch_command(command)
	assert_almost_eq(_entity_poison(ctx), 1.0, 0.001, "the live replay lands it on the entity")
	assert_almost_eq(_poison_power(_core_of(ctx)), 0.0, 0.001)


func test_a_rebuilt_status_lands_on_the_shipped_host_without_rechecking_node_hp() -> void:
	var ctx: Dictionary = await _build()
	var core := _core_of(ctx)
	_crack_shot(ctx)
	var outcome := AttackOutcome.new()
	var hit := RangedDamageFormula.compute(ctx.attacker, ctx.nodes.leaf, core, _POISON_ARROW)
	outcome.hits.append(hit)
	outcome.hits.append(RangedDamageFormula.status_for(hit))
	OutcomeApplier.apply(outcome, CombatWorld.live())
	assert_almost_eq(_entity_poison(ctx), 1.0, 0.001, "sanity: the authority's landing fell through")

	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, ctx.graph)))
	assert_eq(wired[AttackRecord.KEY_HIT_STATUS_HOST][1], int(StatusInstance.HostKind.ENTITY),
			"the landed host crosses the wire")
	var rebuilt := AttackRecord.rebuild(wired, ctx.graph)
	var si := rebuilt.hits[1] as StatusInstance
	assert_not_null(si)
	assert_eq(si.host_kind, StatusInstance.HostKind.ENTITY, "rebuild restores the host")

	# A peer whose core is NOT cracked at replay time still lands on the entity.
	(ctx.defender as Entity).get_combat().clear_statuses()
	core.restore_current_hp(core.get_max_hp())
	si.land_on(core.get_combat(), CombatWorld.live())
	assert_almost_eq(_entity_poison(ctx), 1.0, 0.001, "the shipped host wins over node HP")
	assert_almost_eq(_poison_power(core), 0.0, 0.001)


func test_fall_through_reads_the_entity_boards_resistance_not_the_nodes() -> void:
	var ctx: Dictionary = await _build()
	var core := _core_of(ctx)
	var defender: Entity = ctx.defender
	assert_eq(_POISON_DEF.resistance_stat_id, &"poison_resistance", "the authored def names the stat")
	assert_not_null(defender.stat_board.get_stat(&"poison_resistance"), "the entity board carries it")
	defender.stat_board.get_stat(&"poison_resistance").base_value = 0.5
	_set_local(core, &"poison_resistance", 0.9)
	_crack_shot(ctx)
	_land_poison_arrow(ctx, CombatWorld.live())
	assert_almost_eq(_entity_poison(ctx), 1.0 * (1.0 - 0.5), 0.001,
			"scaled by the ENTITY's resistance (0.5), never the node's local 0.9")
