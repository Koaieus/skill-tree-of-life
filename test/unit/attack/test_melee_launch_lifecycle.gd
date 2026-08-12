extends GutTest

## #406 — BattleSystem.launch_attack()'s melee branch keeps the plan (and its
## attached temp-upgrade addons) live through the whole `await
## melee_preview.launch()` window instead of clearing it up front, gated by
## `is_launching` rather than `attack_plan != null`. Pins the full lifecycle:
## `is_launching` resets after the swing (with and without a temp upgrade
## attached, freeing it), a second attack can be armed afterward, and
## `player_can_act_changed` re-fires so AttackModeBar (gated purely off that
## signal in command_tray.gd, never a fresh poll) doesn't stay disabled for
## the rest of the turn.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _bs: BattleSystem
var _preview: MeleePreview
var _attacker: Entity


func _spawn(nm: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	return sn


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_preview = MeleePreview.new()
	add_child_autofree(_preview)

	_bs = autofree(BattleSystem.new())
	_bs.turn_manager = _tm
	_bs.allocation_system = _alloc
	_bs.graph = _graph
	_bs.melee_preview = _preview
	_preview.battle_system = _bs
	add_child(_bs)
	_preview._ready()

	_attacker = Entity.new()
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_attacker.stat_board.blade_size.base_value = 3.0
	_attacker.stat_board.action_points.set_base_ratcheted(2.0)
	_attacker.stat_board.action_points.current = 2.0
	_graph.add_child(_attacker)
	_tm.current_entity = _attacker


## Pumps frames until `_bs.is_launching` clears or `max_ticks` is exhausted —
## used as the observation point for the bug this file pins: without the
## fix, is_launching never clears and this loop runs out the clock.
func _await_launch_settle(max_ticks: int = 300) -> int:
	var ticks := 0
	while _bs.is_launching and ticks < max_ticks:
		await get_tree().process_frame
		ticks += 1
	return ticks


func test_launch_attack_melee_resets_is_launching_and_allows_a_second_attack() -> void:
	var source := _spawn("Source")
	var joint := _spawn("Joint")
	_graph.add_edge(source, joint)
	await get_tree().process_frame

	_alloc.force_allocate(_attacker, source)
	_alloc.force_allocate(_attacker, joint)

	_bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _bs.attack_plan as MeleeAttackPlan
	plan._on_node_left_clicked(source)
	plan._on_node_left_clicked(joint)
	assert_true(plan.is_valid(), "fixture plan must be valid before launching")

	_bs.launch_attack()
	assert_true(_bs.is_launching, "is_launching should be true immediately after calling launch_attack")

	var ticks := await _await_launch_settle()
	assert_false(_bs.is_launching, "is_launching must reset to false after the melee swing completes (ticks=%d)" % ticks)
	assert_true(_bs.attack_plan == null, "plan should be cleared after the swing")

	# A second attack (spending the turn's remaining AP) must be arm-able —
	# the exact flow that regressed: after the fix landed, request_attack_mode
	# no longer silently no-ops here.
	_bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	assert_not_null(_bs.attack_plan, "a second melee plan must be arm-able after the first swing")
	var plan2 := _bs.attack_plan as MeleeAttackPlan
	plan2._on_node_left_clicked(source)
	plan2._on_node_left_clicked(joint)
	assert_true(plan2.is_valid(), "second plan must be arm-able the same way as the first")


func test_launch_attack_melee_with_temp_upgrade_frees_it_and_resets_is_launching() -> void:
	var source := _spawn("Source")
	var joint := _spawn("Joint")
	var tip := _spawn("Tip")
	_graph.add_edge(source, joint)
	_graph.add_edge(joint, tip)
	await get_tree().process_frame

	_alloc.force_allocate(_attacker, source)
	_alloc.force_allocate(_attacker, joint)
	_alloc.force_allocate(_attacker, tip)

	_bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _bs.attack_plan as MeleeAttackPlan
	plan._on_node_left_clicked(source)
	plan._on_node_left_clicked(joint)
	assert_true(plan.apply_temp_upgrade(joint, MeleeAttackPlan.CLAMP_UPGRADE))
	assert_true(plan.is_valid(), "fixture plan must be valid before launching")

	_bs.launch_attack()
	var ticks := await _await_launch_settle()

	assert_false(_bs.is_launching, "is_launching must reset to false after a swing WITH a temp upgrade attached (ticks=%d)" % ticks)
	assert_true(_bs.attack_plan == null, "plan should be cleared after the swing")
	assert_eq(joint.get_addons().size(), 0, "the temp addon must be freed after the swing completes")


func test_player_can_act_changed_fires_after_swing_reenabling_attack_mode_bar() -> void:
	# AttackModeBar (command_tray.gd) is gated purely off player_can_act_changed
	# — it never polls can_player_act() on its own. can_player_act() reads
	# battle_system.is_launching (#406), whose transitions have no signal of
	# their own; the fix connects the gate-refresh to attack_plan_changed
	# (which _reset() fires) and clears is_launching BEFORE _reset() runs, so
	# the listener doesn't observe a stale "still launching" at that instant.
	var source := _spawn("Source")
	var joint := _spawn("Joint")
	_graph.add_edge(source, joint)
	await get_tree().process_frame
	_alloc.force_allocate(_attacker, source)
	_alloc.force_allocate(_attacker, joint)

	var ctl := PlayerInputController.new()
	ctl.graph = _graph
	ctl.allocation_system = _alloc
	ctl.battle_system = _bs
	ctl.turn_manager = _tm
	ctl.player = _attacker
	add_child_autofree(ctl)

	var emissions: Array[bool] = []
	ctl.player_can_act_changed.connect(func(can_act: bool): emissions.append(can_act))

	_bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _bs.attack_plan as MeleeAttackPlan
	plan._on_node_left_clicked(source)
	plan._on_node_left_clicked(joint)
	_bs.launch_attack()

	await _await_launch_settle()

	assert_true(emissions.has(false), "player_can_act_changed must fire false while the swing is resolving")
	assert_true(emissions.size() >= 2 and emissions[-1] == true,
			"player_can_act_changed must fire true again once the swing completes, or AttackModeBar stays disabled forever (emissions=%s)" % [emissions])
