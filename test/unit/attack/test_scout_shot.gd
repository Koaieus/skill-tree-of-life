extends GutTest

## #1036 — the scout shot. Owner (2026-09-21, hub #949): fog is pushed for
## free by scouting visible nodes and at an AP cost for SENSED (but not
## visible) nodes. A volley at a sensed non-visible node is valid iff every
## arrow in it is a scout arrow, and that volley costs 1 AP; a volley at a
## visible hostile keeps 0 AP whatever it holds. The target may be any sensed
## node, allocated or not — ownership of a sensed node never leaks through
## validation. While a ranged plan is armed with scout stock, BattleSystem
## turns VisionSystem's `pick_sensed` lever on so the sensed node takes the
## click; off again on cancel and after the commit.

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


## Attacker owns core–leaf; the leaf sees 50 px and senses 1 hop, so `target`
## (hostile, 200 px on) and `fog` (unallocated, one hop off the leaf) are
## sensed-not-visible while `neighbour` (two hops) is neither. `near` is a
## hostile node inside the leaf's sight — the visible-hostile control.
func _build(scout_stock: int = 4) -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var nodes: Dictionary = {}
	for entry in [["core", Vector2(0, 0)], ["leaf", Vector2(100, 0)],
			["near", Vector2(130, 0)], ["target", Vector2(300, 0)],
			["fog", Vector2(300, 150)], ["neighbour", Vector2(450, 0)]]:
		var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		node.name = str(entry[0])
		graph.add_skill_node(node)
		node.global_position = entry[1] as Vector2
		nodes[entry[0]] = node
	graph.add_edge(nodes.core, nodes.leaf)
	graph.add_edge(nodes.leaf, nodes.near)
	graph.add_edge(nodes.leaf, nodes.target)
	graph.add_edge(nodes.leaf, nodes.fog)
	graph.add_edge(nodes.target, nodes.neighbour)

	var attacker := Entity.new()
	attacker.display_name = "Attacker"
	attacker.faction = _PLAYER_FACTION
	attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	if scout_stock > 0:
		assert_eq(attacker.stat_board.arrows.add(&"scout", scout_stock), scout_stock, "fixture quiver must hold the scouts")
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
	alloc.force_allocate(defender, nodes.near)
	alloc.force_allocate(defender, nodes.target)
	alloc.force_allocate(defender, nodes.neighbour)
	defender.core_location = nodes.neighbour

	for leaf in [nodes.leaf, nodes.core]:
		_set_local(leaf, &"range", 400.0)
		_set_local(leaf, &"vision_range", 50.0)
		_set_local(leaf, &"sensor_range", 0.0)
	_set_local(nodes.leaf, &"sensor_range", 1.0)
	_set_local(nodes.leaf, &"ranged_damage", 2.0)
	_set_local(nodes.leaf, &"max_shots_per_leaf", 5.0)
	_set_local(nodes.core, &"max_shots_per_leaf", 0.0)

	var vision := VisionSystem.new()
	vision.graph = graph
	vision.allocation_system = alloc
	vision.viewers = [attacker]
	add_child_autofree(vision)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.start_turn(attacker)

	var bs := BattleSystem.new()
	bs.turn_manager = tm
	bs.allocation_system = alloc
	bs.graph = graph
	bs.vision_system = vision
	bs.instant_mutation = true
	add_child_autofree(bs)

	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	vision._recompute()
	assert_true(vision.is_visible(nodes.near), "fixture: near is inside the leaf's sight")
	assert_true(vision.is_sensed(nodes.target) and not vision.is_visible(nodes.target), "fixture: target is sensed-only")
	assert_true(vision.is_sensed(nodes.fog) and not vision.is_visible(nodes.fog), "fixture: fog is sensed-only")
	assert_false(vision.is_sensed(nodes.neighbour) or vision.is_visible(nodes.neighbour), "fixture: neighbour is dark")

	return {"graph": graph, "bs": bs, "vision": vision, "attacker": attacker,
			"defender": defender, "nodes": nodes}


func _arm(ctx: Dictionary, target: SkillNode, counts: Dictionary) -> RangedAttackPlan:
	var bs: BattleSystem = ctx.bs
	bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	var plan := bs.attack_plan as RangedAttackPlan
	plan.handle_left_click(target)
	plan.ammo_counts = counts
	return plan


# ── Validation and AP ───────────────────────────────────────────────────────

func test_an_all_scout_volley_at_a_sensed_hostile_validates_at_one_ap() -> void:
	var ctx: Dictionary = await _build()
	var plan := _arm(ctx, ctx.nodes.target, {&"scout": 2})
	assert_eq(plan.target, ctx.nodes.target, "the click sticks on a sensed node")
	assert_eq(plan.validate(), [] as Array[String], "all-scout at a sensed node is a valid volley")
	assert_eq(plan.ap_cost(), 1, "the scout shot costs 1 AP")


func test_a_mixed_volley_at_a_sensed_node_fails_with_one_error_naming_the_mix() -> void:
	var ctx: Dictionary = await _build()
	var plan := _arm(ctx, ctx.nodes.target, {&"arrow": 1, &"scout": 1})
	var errors := plan.validate()
	assert_eq(errors.size(), 1, "exactly one error: %s" % [errors])
	assert_string_contains(errors[0].to_lower() if errors.size() > 0 else "", "scout", "the error names the composition")


func test_a_visible_hostile_keeps_zero_ap_whatever_the_volley_holds() -> void:
	var ctx: Dictionary = await _build()
	var plan := _arm(ctx, ctx.nodes.near, {&"arrow": 2, &"scout": 1})
	assert_eq(plan.validate(), [] as Array[String], "a mixed volley at a visible hostile validates")
	assert_eq(plan.ap_cost(), 0, "firing at a visible hostile stays free")


func test_an_unallocated_sensed_node_validates_without_an_ownership_read() -> void:
	var ctx: Dictionary = await _build()
	assert_null((ctx.nodes.fog as SkillNode).owned_by, "fixture: fog is unallocated")
	var plan := _arm(ctx, ctx.nodes.fog, {&"scout": 1})
	assert_eq(plan.target, ctx.nodes.fog, "the click sticks on an unallocated sensed node")
	assert_eq(plan.validate(), [] as Array[String], "ownership never enters a sensed target's validation")
	assert_eq(plan.ap_cost(), 1, "still the scout-shot price")


func test_a_dark_node_is_no_target() -> void:
	var ctx: Dictionary = await _build()
	var plan := _arm(ctx, ctx.nodes.neighbour, {&"scout": 1})
	assert_null(plan.target, "neither visible nor sensed: the click does not stick")


func test_the_committed_record_carries_one_ap_and_the_entity_pays_it() -> void:
	var ctx: Dictionary = await _build()
	_arm(ctx, ctx.nodes.target, {&"scout": 2})
	var bs: BattleSystem = ctx.bs
	var ap: Stat = ctx.attacker.stat_board.action_points
	var ap_before: float = ap.current
	var command := bs.build_launch_command()
	assert_not_null(command, "the fixture plan must be launchable")
	assert_true(bs.prepare_launch_command(command), "the scout shot survives validation")
	assert_eq(int(command.record.get(AttackRecord.KEY_AP, -1)), 1, "the record carries the AP write")
	@warning_ignore("redundant_await")
	await bs.apply_launch_command(command)
	assert_eq(ap.current, ap_before - 1.0, "the entity paid 1 AP off the record")


# ── pick_sensed ─────────────────────────────────────────────────────────────

func test_pick_sensed_follows_the_armed_ranged_plan_with_scout_stock() -> void:
	var ctx: Dictionary = await _build()
	var bs: BattleSystem = ctx.bs
	var vision: VisionSystem = ctx.vision
	assert_false(vision.pick_sensed, "off before any plan")
	bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	assert_true(vision.pick_sensed, "on while a ranged plan is armed with scout stock")
	bs.cancel_attack()
	assert_false(vision.pick_sensed, "off after cancel")
	_arm(ctx, ctx.nodes.target, {&"scout": 2})
	assert_true(vision.pick_sensed, "on again for the re-armed plan")
	var command := bs.build_launch_command()
	assert_true(bs.prepare_launch_command(command))
	@warning_ignore("redundant_await")
	await bs.apply_launch_command(command)
	assert_false(vision.pick_sensed, "off after the commit")


func test_pick_sensed_stays_off_without_scout_stock() -> void:
	var ctx: Dictionary = await _build(0)
	var bs: BattleSystem = ctx.bs
	bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	assert_false((ctx.vision as VisionSystem).pick_sensed, "no scouts, no sensed picking")
	bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	assert_false((ctx.vision as VisionSystem).pick_sensed, "a melee plan never picks sensed")
