extends GutTest

## #1035 — the scout arrow. A scout type (`attack/ammo/types/scout.tres`,
## `reveal_fraction > 0`) never deals damage: the resolve emits one
## [RevealInstance] per scout arrow, no [DamageInstance], no [StatusInstance],
## with radius = its own firing leaf's local `vision_range × reveal_fraction ×
## (1 + reveal_stack_bonus·(k−1))`, k counted over the scout arrows from that
## same leaf in landing order. Scouts sit last in the roster order so the disc
## lands once the damage arrows are done. A reveal burns its shot like any
## arrow; the record carries it to a peer as its own kind; reload mints the
## `scout` bin flat off `scout_arrows_per_reload`.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")
const _SCOUT: AmmoType = preload("res://attack/ammo/types/scout.tres")
const _ROSTER: AmmoTypeRoster = preload("res://attack/ammo/ammo_type_roster.tres")


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


func _arm(ctx: Dictionary, counts: Dictionary) -> RangedAttackPlan:
	var bs: BattleSystem = ctx.bs
	bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	var plan := bs.attack_plan as RangedAttackPlan
	plan._on_node_left_clicked(ctx.nodes.target)
	plan.ammo_counts = counts
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
	assert_gt(_SCOUT.reveal_fraction, 0.0, "reveal_fraction > 0 is what makes a type a scout")
	assert_null(_SCOUT.status_def, "never a status_def: the mark is VisionSystem's, not a node status")
	assert_eq(_SCOUT.per_reload_stat_id, &"scout_arrows_per_reload")


# ── The resolve ─────────────────────────────────────────────────────────────

func test_a_volley_of_two_base_and_three_scouts_yields_two_damage_and_three_reveals() -> void:
	var ctx: Dictionary = await _build()
	var outcome := _resolve(ctx, {&"arrow": 2, &"scout": 3})
	assert_eq(outcome.hits.size(), 5, "one hit per arrow, nothing else")
	assert_eq(_of(outcome, DamageInstance).size(), 2)
	assert_eq(_of(outcome, StatusInstance).size(), 0, "a scout arrow leaves no status")
	var reveals: Array = _of(outcome, RevealInstance)
	assert_eq(reveals.size(), 3)
	if reveals.size() != 3:
		return
	var amounts: Array = reveals.map(func(h: HitInstance) -> float: return h.amount)
	assert_almost_eq(amounts[0], 200.0, 0.001, "400 × 0.5 (k=1)")
	assert_almost_eq(amounts[1], 240.0, 0.001, "400 × 0.5 × 1.2 (k=2)")
	assert_almost_eq(amounts[2], 280.0, 0.001, "400 × 0.5 × 1.4 (k=3)")
	for h in reveals:
		assert_eq(h.attacker, ctx.attacker)
		assert_eq(h.origin, ctx.nodes.leaf)
		assert_eq(h.target, ctx.nodes.target)
		assert_eq(h.kind, HitInstance.Kind.REVEAL)
	var last_damage_key: float = _of(outcome, DamageInstance).map(func(h: HitInstance) -> float: return h.structural_key).max()
	for h in reveals:
		assert_true(h.structural_key >= last_damage_key, "scouts are keyed after the damage arrows")


func test_two_leaves_firing_one_scout_each_read_their_own_vision_range() -> void:
	var ctx: Dictionary = await _build(Vector2.ZERO, 1.0, 1.0)
	var outcome := _resolve(ctx, {&"scout": 2})
	var reveals: Array = _of(outcome, RevealInstance)
	assert_eq(reveals.size(), 2)
	if reveals.size() != 2:
		return
	var by_origin: Dictionary = {}
	for h in reveals:
		by_origin[h.origin] = h.amount
	assert_almost_eq(float(by_origin.get(ctx.nodes.leaf, -1.0)), 200.0, 0.001, "the leaf's 400 × 0.5")
	assert_almost_eq(float(by_origin.get(ctx.nodes.core, -1.0)), 350.0, 0.001,
			"the core's 700 × 0.5 — k counts per firing leaf, so no stack bonus")


func test_a_reveal_burns_its_shot_and_its_scout_stock() -> void:
	var ctx: Dictionary = await _build()
	_arm(ctx, {&"arrow": 2, &"scout": 3})
	var bs: BattleSystem = ctx.bs
	var quiver: Quiver = ctx.attacker.stat_board.arrows
	var scouts_before: int = quiver.stock_of(&"scout")
	var command := bs.build_launch_command()
	assert_not_null(command, "the fixture plan must be launchable")
	assert_true(bs.prepare_launch_command(command), "the fixture attack must survive validation")
	@warning_ignore("redundant_await")
	await bs.apply_launch_command(command)
	assert_eq((ctx.nodes.leaf as SkillNode).shots_fired_this_turn, 5, "five arrows, five shots — a reveal is a shot")
	assert_eq(quiver.stock_of(&"scout"), scouts_before - 3, "three from the scout bin")


func test_the_record_round_trips_the_reveals_with_their_amounts_and_attacker() -> void:
	var ctx: Dictionary = await _build()
	var outcome := _resolve(ctx, {&"arrow": 2, &"scout": 3})
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, ctx.graph)))
	var rebuilt := AttackRecord.rebuild(wired, ctx.graph)
	var reveals: Array = _of(rebuilt, RevealInstance)
	assert_eq(reveals.size(), 3, "three reveals come back as their own kind")
	var amounts: Array = reveals.map(func(h: HitInstance) -> float: return h.amount)
	assert_eq(amounts, [200.0, 240.0, 280.0])
	for h in reveals:
		assert_eq(h.attacker, ctx.attacker)


# ── The supply ──────────────────────────────────────────────────────────────

func test_reload_yield_mints_scout_arrows_flat_off_the_board_stat() -> void:
	var ctx: Dictionary = await _build()
	var attacker: Entity = ctx.attacker
	attacker.stat_board.scout_arrows_per_reload.base_value = 2.0
	var y: Dictionary = attacker.reload_yield()
	assert_eq(int(y.get(&"scout", 0)), 2, "entity-flat: 2, not 2 × leaves")
