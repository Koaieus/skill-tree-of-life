extends GutTest

## #474/#504 — VFX never influences the applied world.
##
## World state (target HP, the forced-dealloc cascade) must be IDENTICAL
## whether `attack_vfx` is null or a live AttackVFX node. That is #474's
## acceptance and it still holds: VFX is a pure observer, and the mutation loop
## waits on its own [BeatClock] rather than on any animation, so dropping every
## frame of the volley cannot change what landed.
##
## [b]#474's second half is deliberately gone.[/b] It used to also assert that
## everything landed before `launch_attack()` reached its first `await` — i.e.
## that the whole outcome was observable on the line after an un-awaited call.
## Design B (#504) spreads mutation across each hit's `arrival_time` on
## purpose, so that is no longer true and must not be re-asserted. `is_launching`
## is what tells a caller the world is settled; `instant_mutation` is how a
## fixture asks for the old synchronous shape, and this test uses it so it can
## keep testing VFX-independence rather than timing.
##
## Ranged mode: no physics scan needed (RangedAttackPlan reach is euclidean),
## so the fixture stays simple. Mirrors test_ranged_attack_plan.gd's chain
## A(0,0) - B(200,0) - C(400,0) layout.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")


func _set_range(node: SkillNode, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = &"range"
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


func _set_ranged_damage(node: SkillNode, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = &"ranged_damage"
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


## Builds a fresh graph + attacker + hostile + BattleSystem each call so the
## two scenarios (null vfx / live vfx) never share state.
func _build(with_live_vfx: bool) -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)

	var core := _SKILL_NODE_SCENE.instantiate() as SkillNode
	core.position = Vector2(0, 0)
	graph.add_skill_node(core)

	var leaf := _SKILL_NODE_SCENE.instantiate() as SkillNode
	leaf.position = Vector2(200, 0)
	graph.add_skill_node(leaf)
	graph.add_edge(core, leaf)

	var target := _SKILL_NODE_SCENE.instantiate() as SkillNode
	target.position = Vector2(250, 0)
	graph.add_skill_node(target)

	var attacker := Entity.new()
	attacker.faction = _PLAYER_FACTION
	attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	attacker.stat_board.action_points.set_base_ratcheted(2.0)
	attacker.stat_board.action_points.current = 2.0
	graph.add_child(attacker)

	var hostile := Entity.new()
	hostile.faction = _NPC_FACTION
	hostile.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.add_child(hostile)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(attacker, core)
	alloc.force_allocate(attacker, leaf)
	attacker.core_location = core
	alloc.force_allocate(hostile, target)
	hostile.core_location = target

	_set_range(leaf, 100.0)
	_set_ranged_damage(leaf, 9999.0)  # overkill: guarantees a lethal hit

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.current_entity = attacker

	var bs := BattleSystem.new()
	bs.turn_manager = tm
	bs.allocation_system = alloc
	bs.graph = graph
	# #504: land the outcome in one go, so this test measures VFX-independence
	# and not the beat clock's timing. Deliberately set for BOTH scenarios —
	# including the live-VFX one — since a flag that differed between them
	# would be a second variable in a test with exactly one.
	bs.instant_mutation = true
	add_child_autofree(bs)

	if with_live_vfx:
		var vfx := AttackVFX.new()
		add_child_autofree(vfx)
		bs.attack_vfx = vfx

	return {"bs": bs, "attacker": attacker, "hostile": hostile,
			"core": core, "leaf": leaf, "target": target}


func _fire(ctx: Dictionary) -> void:
	var bs: BattleSystem = ctx.bs
	bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	var plan := bs.attack_plan as RangedAttackPlan
	plan._on_node_left_clicked(ctx.target)
	assert_true(plan.is_valid(), "fixture plan must be valid before launching")
	# Not awaited, and with `instant_mutation` set that is enough: the applier
	# never parks, so resolve() + the whole outcome + the cascade have all run
	# by the time this returns. Without the flag the volley would still be
	# mid-flight here — see the class docstring.
	bs.launch_attack()


func test_world_state_identical_with_null_and_live_attack_vfx() -> void:
	var no_vfx: Dictionary = await _build(false)
	var live_vfx: Dictionary = await _build(true)

	_fire(no_vfx)
	_fire(live_vfx)

	# Both targets took the lethal overkill hit and were force-deallocated by
	# the cascade, identically.
	assert_null((no_vfx.target as SkillNode).owned_by,
			"null-vfx path: cascade already stripped the target")
	assert_null((live_vfx.target as SkillNode).owned_by,
			"live-vfx path: cascade already stripped the target")

	var no_vfx_wounds: float = (no_vfx.hostile as Entity).stat_board.skill_points.wounded
	var live_vfx_wounds: float = (live_vfx.hostile as Entity).stat_board.skill_points.wounded
	assert_almost_eq(no_vfx_wounds, live_vfx_wounds, 0.001,
			"wounded SP must match regardless of attack_vfx wiring")

	var no_vfx_health := (no_vfx.hostile as Entity).stat_board.health.current
	var live_vfx_health := (live_vfx.hostile as Entity).stat_board.health.current
	assert_almost_eq(no_vfx_health, live_vfx_health, 0.001,
			"health chip damage must match regardless of attack_vfx wiring")
