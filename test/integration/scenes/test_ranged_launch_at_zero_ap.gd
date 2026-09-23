extends GutTest

## A volley costs 0 AP (#957, owner 2026-09-18: "Firing costs 0 AP"), so at
## 0 AP the ranged tab and its Launch stay live while melee's Launch does
## not. The gate used to be one blanket "have any AP" clause inside
## `PlayerInputController.can_player_act()`, which dimmed every tab and
## Launch at 0 AP — including the one verb that is free. Flow and
## affordability are now two questions: `can_player_act()` and
## `can_afford(plan)`.
##
## Driven on `dev_sandbox.tscn`: two reloads (1 AP each) are the honest way
## to an empty pool with a full quiver.

const _SANDBOX := preload("res://scenes/dev_sandbox.tscn")

var _root: GameRoot
var _pic: PlayerInputController
var _ap: PoolStat


func before_each() -> void:
	_root = _SANDBOX.instantiate()
	add_child_autofree(_root)
	for _i in 60:
		await wait_physics_frames(1)
		if _root.turn_manager.current_entity != null:
			break
	assert_eq(_root.turn_manager.current_entity, _root.player, "fixture: player holds the first turn")
	_pic = _root.input_ctl
	_ap = _root.player.stat_board.action_points
	_pic.on_attack_mode_requested(BattleSystem.AttackMode.RANGED)
	for _i in 2:
		_pic.request_reload()
		while _root.command_applier.is_applying:
			await _root.command_applier.applying_changed
	await wait_physics_frames(2)
	assert_eq(_ap.available(), 0, "fixture: two reloads empty the pool")


func _body(cls: String) -> Control:
	var found := _root.find_children("*", cls, true, false)
	return found[0] if not found.is_empty() else null


func test_ranged_plan_is_free_and_the_others_are_not() -> void:
	assert_eq((_root.battle_system.attack_plan as AttackPlan).ap_cost(), 0)
	assert_eq(MeleeAttackPlan.new().ap_cost(), 1)
	assert_eq(MagicAttackPlan.new().ap_cost(), 1)
	assert_eq(AttackOutcome.new().ap_cost, 1, "the outcome default is the melee/magic price")


func test_flow_gate_stays_open_at_zero_ap() -> void:
	assert_true(_pic.can_player_act(), "0 AP is not a flow condition")
	assert_true(_pic.can_afford(_root.battle_system.attack_plan), "a volley is affordable at 0 AP")
	var bar := _body("AttackModeBar")
	for btn in bar._group.get_buttons():
		assert_true(btn.enabled, "tab %s live at 0 AP" % btn.name)


func test_ranged_launch_is_live_at_zero_ap_and_fires() -> void:
	var plan := _root.battle_system.attack_plan as RangedAttackPlan
	plan.handle_left_click(_root.graph.get_node("Nodes/Enemy_Core"))
	await wait_physics_frames(2)
	var body := _body("RangedBody")
	assert_true(body._launch_button.enabled, "ranged Launch live at 0 AP")
	assert_eq(plan.resolve().ap_cost, plan.ap_cost(), "resolve stamps the plan's price")
	var before := _root.player.stat_board.arrows.stock_of(&"arrow")
	await _root.battle_system.launch_attack()
	while _root.command_applier.is_applying:
		await _root.command_applier.applying_changed
	assert_lt(_root.player.stat_board.arrows.stock_of(&"arrow"), before, "the volley consumed arrows at 0 AP")


func test_melee_launch_is_dimmed_at_zero_ap() -> void:
	_pic.on_attack_mode_requested(BattleSystem.AttackMode.MELEE)
	await wait_physics_frames(2)
	assert_false(_pic.can_afford(_root.battle_system.attack_plan), "melee costs 1")
	assert_false(_pic.can_reform())
	var body := _body("MeleeBody")
	assert_false(body._launch_button.enabled, "melee Launch dimmed at 0 AP")
