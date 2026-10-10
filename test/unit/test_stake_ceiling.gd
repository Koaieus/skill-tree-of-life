extends GutTest
## `stake_ceiling` is a node-local stat (default 3) read through
## `SkillNode.stake_ceiling`; a procgen stake write is ungated by it and lifts
## it by +1 local modifiers so it never sits below the level procgen wrote.

const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")


func _node() -> SkillNode:
	var n: SkillNode = _NODE_SCENE.instantiate()
	add_child_autofree(n)
	return n


func test_default_ceiling_is_3() -> void:
	assert_eq(_node().stake_ceiling, 3)


func test_procgen_stake_within_the_ceiling_leaves_it() -> void:
	var n := _node()
	EntityFactory.set_procgen_stake(n, 3)
	assert_eq(n.stake_level, 3)
	assert_eq(n.stake_ceiling, 3, "no raise at or below the ceiling")


func test_procgen_stake_past_the_ceiling_raises_it_to_the_level() -> void:
	var n := _node()
	EntityFactory.set_procgen_stake(n, 4)
	assert_eq(n.stake_level, 4, "procgen writes are not gated by the ceiling")
	assert_eq(n.stake_ceiling, 4, "+1 per level past it")
	EntityFactory.set_procgen_stake(n, 6)
	assert_eq(n.stake_level, 6)
	assert_eq(n.stake_ceiling, 6, "a later raise stacks fresh modifiers")


func test_repeat_addon_draws_lift_the_ceiling() -> void:
	var n := _node()
	for count in [2, 3, 4]:
		EntityFactory.set_procgen_stake(n, count)
	assert_eq(n.stake_ceiling, 4)


func test_a_lift_is_not_laddered_by_the_fill() -> void:
	var n := _node()
	EntityFactory.set_procgen_stake(n, 4)
	n.allocation_level = 4
	assert_eq(n.stake_ceiling, 4, "+1 per lift at any allocation level")
