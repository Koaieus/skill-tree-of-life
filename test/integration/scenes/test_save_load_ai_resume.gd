extends "res://test/integration/scenes/save_load_fixture.gd"

## Save between two of an AI's actions; after load the AI resumes and ends
## its turn. See the fixture for the shape.


func test_a_save_between_two_ai_actions_resumes_the_ai() -> void:
	_start_run()
	var root := await _launch(_LEVEL)
	var ai := _ai(root)
	(ai.get_node("AIController") as AIController).turn_delay = 0.3
	var nodes_before := root.graph.get_skill_nodes().filter(
			func(n: SkillNode) -> bool: return n.owned_by == ai).size()
	root.command_applier.submit(EndTurnCommand.new(_human(root).entity_id))
	await wait_until(func() -> bool: return root.turn_manager.current_entity == ai,
			5.0, "fixture: the AI takes the turn")
	# Its first action lands; the save is taken in the pause before the next.
	await wait_until(func() -> bool:
			return root.graph.get_skill_nodes().filter(
					func(n: SkillNode) -> bool: return n.owned_by == ai).size() > nodes_before,
			5.0, "fixture: the AI's first allocation")
	assert_eq(root.turn_manager.current_entity, ai, "fixture: still mid-AI-turn")

	var before := await _save_and_reload(root)
	_assert_same_world(before)
	var loaded_ai := _ai(_root)
	assert_true(loaded_ai.is_taking_turn, "the AI holds the turn after load")
	(loaded_ai.get_node("AIController") as AIController).turn_delay = 0.0
	await wait_until(func() -> bool: return _root.turn_manager.current_entity == _root.player,
			5.0, "the resumed AI finished its turn and handed it on")
