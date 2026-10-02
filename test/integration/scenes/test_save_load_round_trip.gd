extends "res://test/integration/scenes/save_load_fixture.gd"

## Save after the local seat's volley, mid-turn; see the fixture for the shape.


func test_a_save_after_one_volley_resumes_the_same_turn() -> void:
	_start_run()
	var root := await _launch(_LEVEL)
	assert_eq(root.turn_manager.current_entity, _human(root), "fixture: the human opens")
	await _allocate_frontier(root, _human(root), 3)

	var enemy := _ai(root)
	assert_not_null(enemy, "fixture: an AI rival")
	_march_to(root, _human(root), enemy)
	root.input_ctl.on_attack_mode_requested(BattleSystem.AttackMode.RANGED)
	root.input_ctl.request_reload()
	await _settle(root)
	var plan := root.input_ctl.armed_stack.attack_plan() as RangedAttackPlan
	# Aim past the fog: which nodes this seat sees is not what is under test.
	plan.viewer_vision = null
	assert_true(plan.set_target(enemy.core_location), "fixture: the rival core is a target")
	var enemy_hp_before := _territory_hp(root, enemy)
	await root.battle_system.launch_attack(plan)
	await _settle(root)
	assert_eq(_human(root).volleys_launched_this_turn, 1, "fixture: one volley launched")
	assert_lt(_territory_hp(root, enemy), enemy_hp_before, "fixture: the volley did damage")

	var before := await _save_and_reload(root)
	_assert_same_world(before)
	var human := _human(_root)
	assert_eq(human.volleys_launched_this_turn, 1, "the volley budget is not refilled")
	assert_true(human.is_taking_turn, "the human's turn resumed")

	# The turn cursor really resumed: ending it hands the turn on and back.
	_ai(_root).get_node("AIController").turn_delay = 0.0
	_root.command_applier.submit(EndTurnCommand.new(human.entity_id))
	await wait_until(func() -> bool: return _root.turn_manager.current_entity != human,
			5.0, "the turn left the human")
	await wait_until(func() -> bool: return _root.turn_manager.current_entity == human,
			5.0, "the AI handed the turn back")
