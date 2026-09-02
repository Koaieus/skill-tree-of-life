extends GutTest

## The ranged/magic release contract: `is_launching` clears one
## [member BattleSystem.release_beat] after the LAST landing, not after the
## animation has drained.
##
## It used to be the drain, and for a volley that meant the arrow's
## stick-and-fade — `LightArrow.hold_seconds` 0.35 + `fade_seconds` 0.4 on top
## of a 1.5 s schedule (`PresentationTempo.volley_stagger_span` 0.7 +
## `volley_flight_time` 0.8). Three quarters of a second of lockout in which
## nothing about the world could still change.
##
## So this runs on a REAL beat clock (`instant_mutation` stays false — the
## timing IS the subject) and pins both halves: the launch returns while the
## coordinator is demonstrably still animating, and it does not return before
## the world has settled.
##
## Fixture shape borrowed from test_battle_system_outcome_sync.gd — a chain
## core(0,0) - leaf(200,0) with a hostile core at (250,0).

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")


func _set_stat(node: SkillNode, id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


func _build() -> Dictionary:
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
	attacker.stat_board.action_points.base_value = 2.0
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

	_set_stat(leaf, &"range", 100.0)
	_set_stat(leaf, &"ranged_damage", 5.0)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.current_entity = attacker

	var vfx := AttackVFX.new()
	add_child_autofree(vfx)

	var bs := BattleSystem.new()
	bs.turn_manager = tm
	bs.allocation_system = alloc
	bs.graph = graph
	bs.attack_vfx = vfx
	add_child_autofree(bs)

	return {"bs": bs, "vfx": vfx, "target": target, "hostile": hostile}


func test_the_launch_releases_a_beat_after_the_last_landing_not_after_the_drain() -> void:
	var ctx: Dictionary = await _build()
	var bs: BattleSystem = ctx.bs
	var vfx: AttackVFX = ctx.vfx
	var target: SkillNode = ctx.target
	var hp_before: float = target.get_combat().get_current_hp()

	bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	var plan := bs.attack_plan as RangedAttackPlan
	plan._on_node_left_clicked(target)
	assert_true(plan.is_valid(), "fixture plan must be valid before launching")

	await bs.launch_attack()

	assert_false(bs.is_launching, "the launch is released by the time it returns")
	assert_lt(target.get_combat().get_current_hp(), hp_before,
			"…and it did not release EARLY: the volley had already landed")
	# The coordinator is still mounted under %AttackVFX, mid stick-and-fade.
	# That is the whole point of the change — the arrows outlive the lockout.
	assert_gt(vfx.get_child_count(), 0,
			"the volley is still animating, and the player is already free to act")
