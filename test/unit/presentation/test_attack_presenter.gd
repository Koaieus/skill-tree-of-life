extends GutTest

## #1196 — the presenter lives behind a sim-side [AttackStage], and
## [BattleSystem] knows no `ui/` class. #474's contract, restated through the
## stage: a launch with NO stage runs every mode to completion and leaves the
## world exactly as a presented launch does, and a depletion cascade strips in
## the same layer order either way (the order `apply_cascade` strips in is
## observable, so it is not presentation).
##
## Every world is built from the same code; melee's blade-reachable nodes
## coincide with the target at t=0 (the `test_attack_record_replay.gd` trick)
## so the physics scan does not depend on server sync timing.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")
const _PRESENTER_SCENE := preload("res://presentation/attack_presenter.tscn")

## Each world is offset so two live side by side never sweep each other's
## colliders. Positions are not compared — node names are.
var _next_origin := Vector2.ZERO


func _set_local(node: SkillNode, stat_id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


## core - leaf - target - neighbour(defender core), with `tail` hanging off
## `target`: a lethal hit on `target` islands `tail`, so the cascade has two
## layers and an order worth comparing.
func _build(presented: bool) -> Dictionary:
	var origin := _next_origin
	_next_origin += Vector2(100000, 0)
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)

	var nodes: Dictionary = {}
	for entry in [["core", Vector2(0, 0)], ["leaf", Vector2(150, 0)],
			["target", Vector2(150, 0)], ["neighbour", Vector2(300, 0)],
			["tail", Vector2(150, 150)]]:
		var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		node.name = str(entry[0])
		graph.add_skill_node(node)
		node.global_position = origin + (entry[1] as Vector2)
		nodes[entry[0]] = node
	graph.add_edge(nodes.core, nodes.leaf)
	graph.add_edge(nodes.leaf, nodes.target)
	graph.add_edge(nodes.target, nodes.neighbour)
	graph.add_edge(nodes.target, nodes.tail)

	var attacker := Entity.new()
	attacker.display_name = "Attacker"
	attacker.faction = _PLAYER_FACTION
	attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	attacker.stat_board.arrows.add(AmmoTypeRoster.BASE_ID, 40)
	attacker.stat_board.blade_size.base_value = 2.0
	attacker.stat_board.action_points.base_value = 4.0
	attacker.stat_board.action_points.current = 4.0
	attacker.stat_board.mana.base_value = 10.0
	attacker.stat_board.mana.current = 10.0
	# Two independent launches are compared; zero crit so they cannot differ
	# on a roll that has nothing to do with the stage.
	attacker.stat_board.get_stat(&"crit_chance").base_value = 0.0
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
	alloc.force_allocate(defender, nodes.tail)
	defender.core_location = nodes.neighbour

	_set_local(nodes.leaf, &"range", 400.0)
	_set_local(nodes.leaf, &"ranged_damage", 9999.0)
	_set_local(nodes.core, &"blade_damage", 9999.0)
	_set_local(nodes.leaf, &"blade_damage", 9999.0)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.start_turn(attacker)

	var bs := BattleSystem.new()
	bs.turn_manager = tm
	bs.allocation_system = alloc
	bs.graph = graph
	# Both worlds instant, so the stage is the only variable.
	bs.instant_mutation = true
	add_child_autofree(bs)

	var result_presenter: Node = null
	if presented:
		var presenter := _PRESENTER_SCENE.instantiate() as AttackPresenter
		var vfx := AttackVFX.new()
		graph.add_child(vfx)
		var preview := MeleePreview.new()
		preview.battle_system = bs
		graph.add_child(preview)
		presenter.attack_vfx = vfx
		presenter.melee_preview = preview
		add_child(presenter)
		bs.stage = presenter
		result_presenter = presenter

	var layers: Array = []
	bs.cascade_started.connect(func(ls: Array, _d: Entity) -> void:
		for layer in ls:
			layers.append((layer as Array).map(func(n: SkillNode) -> String: return str(n.name))))

	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	return {"bs": bs, "graph": graph, "nodes": nodes, "attacker": attacker,
			"defender": defender, "layers": layers, "presenter": result_presenter}


func _arm(ctx: Dictionary, mode: BattleSystem.AttackMode) -> void:
	var bs: BattleSystem = ctx.bs
	match mode:
		BattleSystem.AttackMode.RANGED:
			bs.request_attack_mode(mode)
			(bs.attack_plan as RangedAttackPlan).handle_left_click(ctx.nodes.target)
		BattleSystem.AttackMode.MELEE:
			bs.request_attack_mode(mode)
			var melee := bs.attack_plan as MeleeAttackPlan
			melee.handle_left_click(ctx.nodes.core)
			melee.handle_left_click(ctx.nodes.leaf)
		BattleSystem.AttackMode.MAGIC:
			bs.selected_spell = SpellCatalog.SPARK
			bs.request_attack_mode(mode)
			var magic := bs.attack_plan as MagicAttackPlan
			magic.handle_left_click(ctx.nodes.leaf)
			magic.handle_left_click(ctx.nodes.target)


## Launch and wait for release, capped in seconds: melee's live swing is a real
## tween that `instant_mutation` does not shorten.
func _launch(ctx: Dictionary, mode: BattleSystem.AttackMode) -> bool:
	_arm(ctx, mode)
	var bs: BattleSystem = ctx.bs
	assert_true(bs.attack_plan != null and bs.attack_plan.is_valid(),
			"fixture plan for mode %d must be valid" % mode)
	bs.launch_attack()
	await wait_until(func() -> bool: return not bs.is_launching, 5.0)
	return not bs.is_launching


func _fingerprint(ctx: Dictionary) -> Dictionary:
	var out := {}
	for key in ctx.nodes:
		var node: SkillNode = ctx.nodes[key]
		out[key] = [str(node.owned_by.display_name) if node.owned_by != null else "",
				snappedf(node.get_current_hp(), 0.001)]
	for role in ["attacker", "defender"]:
		var board: EntityStatBoard = (ctx[role] as Entity).stat_board
		out[role] = [snappedf(board.health.current, 0.001),
				snappedf(board.skill_points.wounded, 0.001),
				snappedf(board.action_points.current, 0.001),
				snappedf(board.mana.current, 0.001)]
	return out


## One world at a time, torn down before the next is built: every
## [BattleSystem] listens on the global `Events` bus, so two live side by side
## would each hear the other's depletions.
func _run(presented: bool, mode: BattleSystem.AttackMode) -> Dictionary:
	var ctx := await _build(presented)
	var done := await _launch(ctx, mode)
	var result := {"done": done, "world": _fingerprint(ctx), "layers": ctx.layers.duplicate()}
	(ctx.bs as Node).free()
	if ctx.presenter != null:
		(ctx.presenter as Node).free()
	(ctx.graph as Node).free()
	await get_tree().process_frame
	return result


func _assert_parity(mode: BattleSystem.AttackMode, lethal: bool = true) -> void:
	var bare := await _run(false, mode)
	var shown := await _run(true, mode)
	assert_true(bare.done, "a stage-less launch (mode %d) must complete" % mode)
	assert_true(shown.done, "a presented launch (mode %d) must complete" % mode)
	assert_eq(bare.world, shown.world,
			"mode %d: the world must be identical with and without a stage" % mode)
	if lethal:
		assert_true((bare.layers as Array).size() >= 2,
				"mode %d: a lethal hit on `target` must cascade `target` then `tail`: %s" % [mode, bare.layers])
	assert_eq(bare.layers, shown.layers,
			"mode %d: the cascade strips in the same layer order with and without a stage" % mode)


func test_battle_system_names_no_ui_presenter() -> void:
	var bs: BattleSystem = autofree(BattleSystem.new())
	assert_false("attack_vfx" in bs, "BattleSystem must not carry an attack_vfx export")
	assert_false("melee_preview" in bs, "BattleSystem must not carry a melee_preview export")
	assert_true("stage" in bs, "BattleSystem reaches its presenter through `stage`")


func test_ranged_is_identical_without_a_stage() -> void:
	await _assert_parity(BattleSystem.AttackMode.RANGED)


func test_magic_is_identical_without_a_stage() -> void:
	# Spark is not lethal on this board, so there is no cascade to order —
	# the world half of the parity still bites.
	await _assert_parity(BattleSystem.AttackMode.MAGIC, false)


func test_melee_is_identical_without_a_stage() -> void:
	await _assert_parity(BattleSystem.AttackMode.MELEE)
