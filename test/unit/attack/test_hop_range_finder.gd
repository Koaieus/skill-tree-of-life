extends GutTest

## HopRangeFinder.effective_max_hops() — the authored `max_hops` folded as the
## base under `cast_range_hops`. A flat ADD_BASE on the stat is the same +N for
## every spell regardless of its authored length (INT's own ladder is flat for
## exactly that reason); a percent is still a percent, and the INT stat floors
## the total once.


## Hand-built, no intrinsics — the shipped INT line is the owner's to tune.
func _board_with_hops_mod(op: StatModifier.Operation, value: float) -> EntityStatBoard:
	var board := EntityStatBoard.new()
	var s := ScalarStat.new()
	s.definition = StatRegistry.get_def(&"cast_range_hops")
	s.base_value = 0.0
	board.set(&"cast_range_hops", s)
	var mod := StatModifier.new()
	mod.stat_id = &"cast_range_hops"
	mod.operation = op
	mod.value = value
	board.add_modifier(mod)
	return board


func test_flat_add_base_grants_the_same_delta_to_short_and_long_spells() -> void:
	var board := _board_with_hops_mod(StatModifier.Operation.ADD_BASE, 3.0)
	var short_finder := HopRangeFinder.new()
	short_finder.max_hops = 2
	var long_finder := HopRangeFinder.new()
	long_finder.max_hops = 10

	assert_eq(short_finder.effective_max_hops(null, null, board), 5, "2 + 3")
	assert_eq(long_finder.effective_max_hops(null, null, board), 13, "10 + 3")


func test_percent_increase_scales_the_authored_hops_and_floors_once() -> void:
	var board := _board_with_hops_mod(StatModifier.Operation.INCREASE, 50.0)
	var finder := HopRangeFinder.new()
	finder.max_hops = 3

	assert_eq(finder.effective_max_hops(null, null, board), 4, "3 × 1.5 = 4.5 → 4")


func test_effective_max_hops_with_no_board_or_attacker_is_unscaled() -> void:
	var finder := HopRangeFinder.new()
	finder.max_hops = 4

	assert_eq(finder.effective_max_hops(null, null, null), 4)
