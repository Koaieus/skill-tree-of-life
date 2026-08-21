extends GutTest

## [method StatBoard.clone_live]'s contract: a clone is a board you may go on to
## MUTATE, not merely read.
##
## The regression these pin (found 2026-08-21, while sizing #498 step 3): the
## clone carried every stat's bin tally but not the `_modifiers` list it was
## folded from, and [method Stat._resync_bins_if_trivial] wipes the bins
## whenever that list holds 0 or 1 entries. So the FIRST modifier added to a
## clone threw the whole copied tally away — a board reading 40 STR came back
## 20 after a +10, with no error on any path. Removal was symmetric.

const _BOARD := preload("res://entity/default_entity_board.tres")


func _live_board() -> StatBoard:
	var b: StatBoard = _BOARD.duplicate(true)
	b.apply_intrinsics()
	return b


func _add_base(id: StringName, v: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = v
	return m


func test_clone_reads_the_same_as_its_source() -> void:
	var src := _live_board()
	for i in 3:
		src.add_modifier(_add_base(&"strength", 10.0))
	var dst := src.clone_live()
	assert_eq(dst.get_stat(&"strength").get_value(), src.get_stat(&"strength").get_value(),
		"a fresh clone reads exactly what its source reads")


func test_adding_a_modifier_to_a_clone_adds_to_the_copied_tally() -> void:
	var src := _live_board()
	for i in 3:
		src.add_modifier(_add_base(&"strength", 10.0))
	var before := float(src.get_stat(&"strength").get_value())

	var dst := src.clone_live()
	dst.add_modifier(_add_base(&"strength", 10.0))

	assert_eq(float(dst.get_stat(&"strength").get_value()), before + 10.0,
		"the clone's +10 must land ON TOP of the copied tally, not replace it")
	assert_eq(float(src.get_stat(&"strength").get_value()), before,
		"and it must not touch the source board")


func test_removing_a_modifier_from_a_clone_subtracts_from_the_copied_tally() -> void:
	var src := _live_board()
	var shared := _add_base(&"strength", 10.0)
	src.add_modifier(shared)
	src.add_modifier(_add_base(&"strength", 10.0))
	var before := float(src.get_stat(&"strength").get_value())

	var dst := src.clone_live()
	# Removal is by identity, and the clone shares the source's instances (#377)
	# — so the handle a caller already holds is the handle that works.
	dst.remove_modifier(shared)

	assert_eq(float(dst.get_stat(&"strength").get_value()), before - 10.0,
		"the clone's removal must subtract exactly that modifier's contribution")
	assert_eq(float(src.get_stat(&"strength").get_value()), before,
		"and it must not touch the source board")


func test_a_clones_modifier_list_is_its_own_array() -> void:
	var src := _live_board()
	var shared := _add_base(&"strength", 10.0)
	src.add_modifier(shared)
	var dst := src.clone_live()
	dst.remove_modifier(shared)
	assert_true(src.get_stat(&"strength").has_modifier(shared),
		"erasing from the clone's list must not erase from the source's")
	assert_false(dst.get_stat(&"strength").has_modifier(shared))


func test_a_clone_of_a_clone_still_carries_the_tally() -> void:
	var src := _live_board()
	for i in 3:
		src.add_modifier(_add_base(&"strength", 10.0))
	var expected := float(src.get_stat(&"strength").get_value())
	var twice := src.clone_live().clone_live()
	twice.add_modifier(_add_base(&"strength", 10.0))
	assert_eq(float(twice.get_stat(&"strength").get_value()), expected + 10.0,
		"a shadow snapshotted from a shadow is the AI-rollout case; it must not decay")
