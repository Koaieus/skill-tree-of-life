extends GutTest

## `ui_reload` (physical R) is ONE action whose meaning belongs to the armed
## level: a ranged plan reloads its quiver (#957), a melee plan re-forms the
## last blade (#466), and the two handlers are never live at the same time —
## the armed mode owns the verb, the controller only walks the stack. Pinned
## here because the first cut had both handlers in the controller on the same
## raw key, ordered by an `if` chain, and a refused quiver reload fell through
## into "arm melee".

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _bs: BattleSystem
var _applier: CommandApplier
var _pic: PlayerInputController
var _attacker: Entity
var _pivot: SkillNode
var _joint: SkillNode
var _submitted: Array[Command] = []


func _spawn(nm: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	return sn


func before_each() -> void:
	_submitted = []
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_tm = autofree(TurnManager.new())
	add_child(_tm)
	_bs = autofree(BattleSystem.new())
	_bs.turn_manager = _tm
	_bs.allocation_system = _alloc
	_bs.graph = _graph
	add_child(_bs)
	# NOT `var x := autofree(...)` — autofree() is untyped, the file would be
	# skipped-but-green.
	_applier = CommandApplier.new()
	autofree(_applier)
	_applier.graph = _graph
	_applier.allocation_system = _alloc
	_applier.battle_system = _bs
	_applier.turn_manager = _tm
	add_child(_applier)
	_bs.command_applier = _applier
	_applier.command_applied.connect(func(c: Command, _ok: bool) -> void: _submitted.append(c))

	_attacker = Entity.new()
	_attacker.name = "Attacker"
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_attacker.stat_board.blade_size.base_value = 3.0
	_attacker.stat_board.action_points.base_value = 4.0
	_attacker.stat_board.action_points.current = 4.0
	# entities_container: `entity_id` mints on entry there, and the applier
	# resolves a command's actor by that id.
	_graph.entities_container.add_child(_attacker)
	_tm.start_turn(_attacker)

	_pivot = _spawn("Pivot")
	_joint = _spawn("Joint")
	_graph.add_edge(_pivot, _joint)
	await get_tree().process_frame
	for n in [_pivot, _joint]:
		_alloc.force_allocate(_attacker, n)

	_pic = autofree(PlayerInputController.new())
	_pic.graph = _graph
	_pic.allocation_system = _alloc
	_pic.battle_system = _bs
	_pic.turn_manager = _tm
	_pic.command_applier = _applier
	_pic.player = _attacker
	add_child(_pic)


func _launch_blade_and_settle() -> void:
	_bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	_pic.route_left_click(_pivot)
	_pic.route_left_click(_joint)
	_bs.launch_attack()
	await wait_until(func() -> bool: return not _bs.is_launching and not _applier.is_applying, 5.0)
	_submitted = []  # only what happens AFTER the launch is under test


func test_ranged_armed_reloads_the_quiver_and_never_arms_melee() -> void:
	await _launch_blade_and_settle()
	_bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	assert_true(_pic.reload_in_hand(), "the ranged level consumes the action")
	assert_true(_bs.attack_plan is RangedAttackPlan, "still ranged — the blade handler was not live")
	await wait_until(func() -> bool: return not _applier.is_applying, 5.0)
	assert_eq(_submitted.size(), 1)
	assert_true(_submitted[0] is ReloadCommand)


func test_ranged_armed_with_nothing_to_reload_is_still_consumed() -> void:
	await _launch_blade_and_settle()
	_bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	_attacker.stat_board.action_points.set_current(0.0)
	assert_false(_attacker.can_reload(), "fixture: no AP, no reload")
	assert_true(_pic.reload_in_hand(), "the armed level owns the key even when it refuses")
	assert_true(_bs.attack_plan is RangedAttackPlan, "a refused reload must not fall through into melee")
	assert_eq(_submitted.size(), 0)


func test_melee_armed_reforms_the_blade_and_never_touches_the_quiver() -> void:
	await _launch_blade_and_settle()
	_bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	assert_true(_pic.reload_in_hand())
	var plan := _bs.attack_plan as MeleeAttackPlan
	assert_not_null(plan)
	assert_eq(plan.source, _pivot, "the last blade is back in hand")
	assert_eq(_submitted.size(), 0, "no ReloadCommand — the quiver handler was not live")


func test_unarmed_reforms_the_last_blade_as_the_global_accelerator() -> void:
	await _launch_blade_and_settle()
	assert_null(_bs.attack_plan, "fixture: nothing armed after the launch")
	assert_true(_pic.reload_in_hand())
	assert_true(_bs.attack_plan is MeleeAttackPlan, "#466: R from nowhere arms melee with the last blade")


func test_unarmed_with_nothing_to_reform_leaves_the_key_unhandled() -> void:
	assert_false(_pic.reload_in_hand())
	assert_null(_bs.attack_plan)
