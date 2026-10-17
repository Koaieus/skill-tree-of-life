extends GutTest
## Ring points: the milestone level mints one ring point (a pool stat) instead
## of its old extra skill point. Asserts are ratios of the export, never 5.

const _BOARD := preload("res://entity/default_entity_board.tres")


func _make_entity() -> Entity:
	var ent := Entity.new()
	autofree(ent)
	ent.display_name = "T"
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	add_child(ent)
	await get_tree().process_frame
	return ent


func _level_to(ent: Entity, lvl: int) -> void:
	while int(ent.level) < lvl:
		ent._on_xp_replenished()


func test_each_milestone_mints_one_ring_point() -> void:
	var ent: Entity = await _make_entity()
	var pool := ent.stat_board.ring_points
	assert_not_null(pool, "the entity board carries ring_points")
	if pool == null:
		return
	var n := ent.milestone_level_interval
	assert_gt(n, 0, "sanity: milestones enabled by default")
	watch_signals(Events)
	_level_to(ent, n - 1)
	assert_eq(int(pool.get_value()), 0, "no point before the first milestone")
	_level_to(ent, n)
	assert_eq(int(pool.get_value()), 1, "cap 1 at the first milestone")
	assert_eq(pool.available(), 1, "current 1")
	assert_signal_emitted(Events, "ring_point_minted")
	var none: Array[StatModifier] = []
	assert_true(ent.buy_ring_cell(&"BleedingT1", none, 1), "a funded buy lands")
	assert_eq(pool.available(), 0, "buying spends the point")
	_level_to(ent, 2 * n)
	assert_eq(int(pool.get_value()), 2, "cap 2 at the second milestone")
	assert_eq(pool.available(), 1, "current 1 after one spent")


func test_interval_zero_mints_none() -> void:
	var ent: Entity = await _make_entity()
	var pool := ent.stat_board.ring_points
	assert_not_null(pool)
	if pool == null:
		return
	ent.milestone_level_interval = 0
	_level_to(ent, 12)
	assert_eq(int(pool.get_value()), 0, "interval 0 disables the mint")


func test_the_milestone_no_longer_mints_an_extra_skill_point() -> void:
	var ent: Entity = await _make_entity()
	var n := ent.milestone_level_interval
	assert_eq(ent.sp_minted_for_level(n), ent.sp_minted_for_level(n + 1),
			"the milestone slot pays a ring point, not SP")
	assert_eq(ent.sp_minted_for_level(2 * n), ent.sp_minted_for_level(2 * n - 1))
