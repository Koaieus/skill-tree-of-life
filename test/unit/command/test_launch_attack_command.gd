extends GutTest

## #511 — an attack is an ordinary confirmed command.
##
## What this pins that `test_attack_record_replay.gd` does not: the ROUTING.
## [method BattleSystem.launch_attack] still awaits the whole action for every
## caller that already existed, the work now happens inside the applier's
## serial queue, and a command raised mid-attack queues rather than
## re-entering.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

var _graph: Graph
var _bs: BattleSystem
var _applier: CommandApplier
var _attacker: Entity
var _defender: Entity
var _nodes: Dictionary = {}


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	# "spare" is unowned and adjacent to the core — the one node in this fixture
	# an allocate can legally take, which the interleaving test needs.
	for entry in [["core", Vector2(0, 0)], ["leaf", Vector2(150, 0)],
			["target", Vector2(300, 0)], ["spare", Vector2(0, 150)]]:
		var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		node.name = str(entry[0])
		_graph.add_skill_node(node)
		node.global_position = entry[1]
		_nodes[entry[0]] = node
	_graph.add_edge(_nodes.core, _nodes.leaf)
	_graph.add_edge(_nodes.leaf, _nodes.target)
	_graph.add_edge(_nodes.core, _nodes.spare)

	_attacker = Entity.new()
	_attacker.faction = _PLAYER_FACTION
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_attacker.stat_board.action_points.set_base_ratcheted(4.0)
	_graph.entities_container.add_child(_attacker)
	_defender = Entity.new()
	_defender.faction = _NPC_FACTION
	_defender.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_defender)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = _graph
	add_child_autofree(alloc)
	alloc.force_allocate(_attacker, _nodes.core)
	alloc.force_allocate(_attacker, _nodes.leaf)
	_attacker.core_location = _nodes.core
	alloc.force_allocate(_defender, _nodes.target)
	_defender.core_location = _nodes.target
	_set_local(_nodes.leaf, &"range", 400.0)
	_set_local(_nodes.leaf, &"ranged_damage", 3.0)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.current_entity = _attacker

	_bs = BattleSystem.new()
	_bs.turn_manager = tm
	_bs.allocation_system = alloc
	_bs.graph = _graph
	_bs.instant_mutation = true
	add_child_autofree(_bs)

	_applier = CommandApplier.new()
	_applier.graph = _graph
	_applier.allocation_system = alloc
	_applier.battle_system = _bs
	_applier.turn_manager = tm
	add_child_autofree(_applier)
	await get_tree().process_frame


func _set_local(node: SkillNode, stat_id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


func _arm() -> void:
	_bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	(_bs.attack_plan as RangedAttackPlan)._on_node_left_clicked(_nodes.target)


func test_the_applier_claims_the_battle_system_at_ready() -> void:
	# One wiring point, not two: the applier a launch submits to and the
	# applier that applies it must be the same object by construction.
	assert_eq(_bs.command_applier, _applier)


func test_launch_attack_routes_through_the_applier() -> void:
	var applied: Array[Command] = []
	_applier.command_applied.connect(func(cmd: Command, ok: bool):
		if ok:
			applied.append(cmd))
	_arm()
	await _bs.launch_attack()
	assert_eq(applied.size(), 1, "exactly one command was applied")
	assert_true(applied[0] is LaunchAttackCommand)
	assert_eq(applied[0].type_tag(), LaunchAttackCommand.TAG)


func test_the_confirmed_command_carries_the_record_out() -> void:
	# CommandLink encodes on `command_confirmed`, which BattleSystem raises the
	# instant the record is stamped — so the record rides out with the
	# broadcast for free. If this ever went empty, every peer would silently
	# receive an initiate. (`test_melee_launch_lifecycle.gd` pins the other
	# half: that this fires before the swing has finished drawing.)
	var seen: Array[LaunchAttackCommand] = []
	_applier.command_confirmed.connect(func(cmd: Command):
		if cmd is LaunchAttackCommand:
			seen.append(cmd as LaunchAttackCommand))
	_arm()
	await _bs.launch_attack()
	assert_eq(seen.size(), 1)
	assert_false(seen[0].record.is_empty(),
			"the record must be stamped by the time command_confirmed fires")
	assert_false(seen[0].plan.is_empty(), "and the plan rides along for the peer's VFX")


func test_launch_attack_still_awaits_the_whole_action() -> void:
	# The contract every existing caller depends on — the HUD launch buttons
	# and AiController's `await bs.launch_attack()`. Routing through a queue
	# must not turn it into fire-and-forget.
	_arm()
	await _bs.launch_attack()
	assert_false(_bs.is_launching, "is_launching is released by the time the await returns")
	assert_null(_bs.attack_plan, "…and the plan is cleared, adjacent to that flip")
	assert_false(_applier.is_applying, "the queue drained too")


func test_is_launching_is_true_while_the_attack_is_in_flight() -> void:
	# Not awaited: `submit` drains synchronously up to the mutation loop's
	# first await, so the flag is observable on the very next line. With
	# `instant_mutation` there is no await at all and it has already settled —
	# so this asserts through a listener instead of on the next line.
	var seen: Array[bool] = []
	_bs.attack_launched.connect(func(_mode, _spell): seen.append(_bs.is_launching))
	_arm()
	await _bs.launch_attack()
	assert_eq(seen, [true] as Array[bool],
			"is_launching spans the action, and attack_launched fires inside it")


func test_a_command_raised_during_an_attack_queues_rather_than_re_entering() -> void:
	# The guard #510 shipped, now exercised by the one verb that can take
	# seconds. An allocate submitted from inside the attack's own application
	# must land AFTER it, not inside it.
	var order: Array[String] = []
	_applier.command_applied.connect(func(cmd: Command, _ok: bool):
		order.append(str(cmd.type_tag())))
	# The same order on the WIRE. `command_confirmed` fires mid-apply for an
	# attack, so this is where interleaving would show up first: a command
	# raised during the swing must still be broadcast after it, or a peer
	# would receive the two in an order the host never applied them in.
	var wire: Array[String] = []
	_applier.command_confirmed.connect(func(cmd: Command):
		wire.append(str(cmd.type_tag())))
	_bs.attack_launched.connect(func(_mode, _spell):
		_applier.submit(AllocateCommand.new(_attacker.entity_id,
				_graph.get_stable_id(_nodes.spare))))
	_arm()
	await _bs.launch_attack()
	assert_eq(order, ["launch_attack", "allocate"] as Array[String],
			"the attack finished before the command it raised")
	assert_eq(wire, ["launch_attack", "allocate"] as Array[String],
			"and it crosses the wire in that same order")


func test_an_initiate_with_no_live_plan_is_refused_rather_than_guessed() -> void:
	# Rebuilding a plan from an initiate is the intent-up path (#463). Until
	# then, a peer handed one refuses loudly instead of inventing a swing.
	var command := LaunchAttackCommand.new(_attacker.entity_id, {}, 1234)
	var applied: Array[bool] = []
	_applier.command_applied.connect(func(_cmd: Command, ok: bool): applied.append(ok))
	_applier.submit(command)
	if _applier.is_applying:
		await _applier.applying_changed
	assert_eq(applied, [false] as Array[bool], "refused, and it did not stall the queue")
