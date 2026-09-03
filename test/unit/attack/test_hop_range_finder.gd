extends GutTest

## HopRangeFinder.effective_max_hops() — additive spell_hops scaling (#727).
## The old rule was `round(max_hops * spell_range_multiplier)`, which is
## regressive: the same INT bonus buys a short spell fewer extra hops than a
## long one. The additive rule grants every spell the SAME flat delta, which
## a multiplicative implementation cannot satisfy — that is exactly the
## property this file pins.


func _board_with_spell_hops(n: float) -> EntityStatBoard:
	var board: EntityStatBoard = preload("res://entity/default_entity_board.tres").duplicate(true)
	var mod := StatModifier.new()
	mod.stat_id = &"spell_hops"
	mod.operation = StatModifier.Operation.SET
	mod.value = n
	board.add_modifier(mod)
	return board


func test_effective_max_hops_is_additive_not_multiplicative() -> void:
	var board := _board_with_spell_hops(3.0)
	var short_finder := HopRangeFinder.new()
	short_finder.max_hops = 2
	var long_finder := HopRangeFinder.new()
	long_finder.max_hops = 10

	var short_delta: int = short_finder.effective_max_hops(null, null, board) - short_finder.max_hops
	var long_delta: int = long_finder.effective_max_hops(null, null, board) - long_finder.max_hops

	assert_eq(short_delta, 3, "a 2-hop spell must get the full flat bonus")
	assert_eq(long_delta, 3, "a 10-hop spell must get the SAME flat bonus, not a proportional one")
	assert_eq(short_delta, long_delta,
			"additive: identical bonus regardless of the spell's authored length")


func test_effective_max_hops_with_no_board_or_attacker_is_unscaled() -> void:
	var finder := HopRangeFinder.new()
	finder.max_hops = 4

	assert_eq(finder.effective_max_hops(null, null, null), 4)
