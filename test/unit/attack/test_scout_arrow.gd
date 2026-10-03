extends GutTest

## The scout arrow (`attack/ammo/types/scout.tres`, #1346). A scout type
## ([method AmmoType.is_scout]) deals no damage: `damage_scale` 0 makes each
## arrow a zero carrier, and its one rider lands one `scout` stack
## ([ScoutStatus], power 1) paired to it — the common compute + riders path,
## no branch of its own. Scouts sit last in the roster order so the disc lands
## once the damage arrows are done. A scout burns its shot like any arrow;
## reload mints the `scout` bin flat off `scout_aspect`.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")
const _SCOUT: AmmoType = preload("res://attack/ammo/types/scout.tres")
const _ROSTER: AmmoTypeRoster = preload("res://attack/ammo/ammo_type_roster.tres")
const _SCOUTED: ScoutStatus = preload("res://effects/status/scouted.tres")


func _set_local(node: SkillNode, stat_id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


## Attacker owns core–leaf, defender owns target–neighbour. The leaf sits ON
## the target (distance 0) and the core 150 away, so wave-major nearest-first
## ranks leaf before core; `core_shots` 0 makes the leaf the sole firer.
func _build(origin: Vector2 = Vector2.ZERO, leaf_shots: float = 5.0, core_shots: float = 0.0) -> Dictionary:
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
	assert_eq(attacker.stat_board.arrows.add(&"scout", 4), 4, "fixture quiver must hold the scouts")
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
	_set_local(nodes.core, &"range", 400.0)
	_set_local(nodes.leaf, &"ranged_damage", 2.0)
	_set_local(nodes.leaf, &"max_shots_per_leaf", leaf_shots)
	_set_local(nodes.core, &"max_shots_per_leaf", core_shots)
	_set_local(nodes.leaf, &"vision_range", 400.0)
	_set_local(nodes.core, &"vision_range", 700.0)

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

	return {"graph": graph, "bs": bs, "attacker": attacker,
			"defender": defender, "nodes": nodes}


## The plan the last `_arm*` minted — what the launch-command builders take.
var _armed: AttackPlan = null


func _arm(ctx: Dictionary, counts: Dictionary) -> RangedAttackPlan:
	var bs: BattleSystem = ctx.bs
	var plan := bs.new_plan(BattleSystem.AttackMode.RANGED, bs.turn_manager.current_entity) as RangedAttackPlan
	plan.set_target(ctx.nodes.target)
	plan.ammo_counts = counts
	_armed = plan
	return plan


func _resolve(ctx: Dictionary, counts: Dictionary) -> AttackOutcome:
	var plan := _arm(ctx, counts)
	var w := CombatWorld.shadow()
	var outcome := plan.resolve_against(w)
	w.free_shadow()
	return outcome


func _of(outcome: AttackOutcome, cls: Variant) -> Array:
	return outcome.hits.filter(func(h: HitInstance) -> bool: return is_instance_of(h, cls))


# ── The type ────────────────────────────────────────────────────────────────

func test_scout_is_rostered_last_with_the_authored_knobs() -> void:
	var sorted := _ROSTER.sorted()
	assert_eq(sorted.back().id, &"scout", "scouts land after every damage arrow")
	assert_true(_SCOUT.is_scout(), "a scouted rider is what makes a type a scout")
	assert_eq(_SCOUT.damage_scale, 0.0, "no damage payload (ADR 0033)")
	assert_eq(_SCOUT.on_hit_effects.size(), 1, "one rider")
	var rider := _SCOUT.on_hit_effects[0] as ApplyStatusEffect
	assert_not_null(rider, "the rider is a status application")
	if rider != null:
		assert_eq(rider.def, _SCOUTED)
		assert_eq(rider.power, 1.0, "1 stack per arrow")
	assert_eq(_SCOUT.per_reload_stat_id, &"scout_aspect")
	for t in sorted:
		if t.id != &"scout":
			assert_false(t.is_scout(), "%s is no scout" % t.id)


# ── The resolve ─────────────────────────────────────────────────────────────

func _scout_carriers(outcome: AttackOutcome) -> Array:
	return _of(outcome, DamageInstance).filter(func(h: HitInstance) -> bool:
		return h is RangedDamageFormula.RangedHitInstance and h.ammo_type == _SCOUT)


func test_a_scout_arrow_emits_one_scout_status_and_no_damage() -> void:
	var ctx: Dictionary = await _build()
	var outcome := _resolve(ctx, {&"scout": 1})
	var statuses: Array = _of(outcome, StatusInstance)
	assert_eq(statuses.size(), 1, "exactly one StatusInstance")
	if statuses.size() == 1:
		assert_eq(statuses[0].def, _SCOUTED)
		assert_eq(statuses[0].power, 1.0, "scout, power 1")
		assert_eq(statuses[0].target, ctx.nodes.target)
	for h in _of(outcome, DamageInstance):
		assert_eq(h.amount, 0.0, "the carrier deals nothing")
		assert_eq(h.effective_amount, 0.0)
		assert_true(h.landed(), "a zero carrier that reaches the node lands, so its rider does")


func test_two_base_and_three_scouts_land_two_damage_hits_and_three_stacks() -> void:
	var ctx: Dictionary = await _build()
	var outcome := _resolve(ctx, {&"arrow": 2, &"scout": 3})
	var carriers := _scout_carriers(outcome)
	assert_eq(carriers.size(), 3, "one zero carrier per scout arrow")
	var damage := _of(outcome, DamageInstance).filter(func(h: HitInstance) -> bool: return h.amount > 0.0)
	assert_eq(damage.size(), 2, "the base arrows still hit")
	var statuses: Array = _of(outcome, StatusInstance)
	assert_eq(statuses.size(), 3, "one stack per scout arrow")
	for st in statuses:
		assert_eq(st.def, _SCOUTED)
		assert_true(carriers.has(st.paired), "each stack rides its own arrow")
	var last_damage_key: float = damage.map(func(h: HitInstance) -> float: return h.structural_key).max()
	for h in carriers:
		assert_true(h.structural_key >= last_damage_key, "scouts are keyed after the damage arrows")


func test_a_scout_burns_its_shot_and_its_scout_stock() -> void:
	var ctx: Dictionary = await _build()
	_arm(ctx, {&"arrow": 2, &"scout": 3})
	var bs: BattleSystem = ctx.bs
	var quiver: Quiver = ctx.attacker.stat_board.arrows
	var scouts_before: int = quiver.stock_of(&"scout")
	var command := bs.build_launch_command(_armed)
	assert_not_null(command, "the fixture plan must be launchable")
	assert_true(bs.prepare_launch_command(command), "the fixture attack must survive validation")
	@warning_ignore("redundant_await")
	await bs.apply_launch_command(command)
	assert_eq((ctx.nodes.leaf as SkillNode).shots_fired_this_turn, 5, "five arrows, five shots — a scout is a shot")
	assert_eq(quiver.stock_of(&"scout"), scouts_before - 3, "three from the scout bin")


# ── The supply ──────────────────────────────────────────────────────────────

func test_reload_yield_mints_scout_arrows_flat_off_the_board_stat() -> void:
	var ctx: Dictionary = await _build()
	var attacker: Entity = ctx.attacker
	attacker.stat_board.scout_aspect.base_value = 2.0
	var y: Dictionary = attacker.reload_yield()
	assert_eq(int(y.get(&"scout", 0)), 2, "entity-flat: 2, not 2 × leaves")
