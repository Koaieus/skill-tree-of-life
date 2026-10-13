extends GutTest

## The XP economy's shape: the level curve, kill payouts and passive income
## agree with each other. Every number is read off the shipped knobs (default
## board, blocker boards, `xp.tres`, LootSystem, the blockers module); these
## assert relations, never a literal default.

const BOARD := preload("res://entity/default_entity_board.tres")
const BLOCKER_SMALL := preload("res://entity/blocker/blocker_small_board.tres")
const BLOCKER_MEDIUM := preload("res://entity/blocker/blocker_medium_board.tres")
const BLOCKER_LARGE := preload("res://entity/blocker/blocker_large_board.tres")
const XP_DEF := preload("res://stats_system/defs/xp.tres")


func _lv1(source: EntityStatBoard) -> EntityStatBoard:
	var b := source.duplicate(true) as EntityStatBoard
	b.apply_intrinsics()
	return b


## The xp cap at level `level` for a fresh lv1 default board, grown the way
## `GrowablePoolStatDef.on_pool_filled` grows it.
func _cap(level: int) -> float:
	var cap := float(_lv1(BOARD).xp.get_value())
	for _l in range(1, level):
		cap = _grow(cap)
	return cap


func _grow(cap: float) -> float:
	var raw := cap * XP_DEF.growth_factor + XP_DEF.growth_flat
	return float(int(raw)) if XP_DEF.value_type == StatDef.ValueType.INT else raw


## Levels gained from lv1 by one lump of `xp` (OVERFLOW cascade, fill on >=).
func _levels_from_lv1(xp: float) -> int:
	var cap := _cap(1)
	var gained := 0
	while xp >= cap:
		xp -= cap
		cap = _grow(cap)
		gained += 1
	return gained


## Max XP a Dormant Core of `size` pays: its largest footprint plus its core,
## at the per-node rate, plus the board's core bonus.
func _max_kill_xp(board: EntityStatBoard, size: int) -> float:
	var loot := LootSystem.new()
	var per_node := loot.xp_per_node_killed
	loot.free()
	var nodes := GraphProcgenBlockers.new().footprint_range(size).y + 1
	return per_node * float(nodes) + float(_lv1(board).core_kill_xp.get_value())


func test_no_single_early_dormant_core_kill_is_a_runaway() -> void:
	var boards := [BLOCKER_SMALL, BLOCKER_MEDIUM, BLOCKER_LARGE]
	for size in 3:
		var xp := _max_kill_xp(boards[size], size)
		assert_lte(_levels_from_lv1(xp), size + 1,
				"size %d Dormant Core: %.0f XP from lv1 gains at most %d levels" % [size, xp, size + 1])


func test_core_kill_xp_tiers_double_and_an_entity_is_the_large_tier() -> void:
	var small := float(_lv1(BLOCKER_SMALL).core_kill_xp.get_value())
	var medium := float(_lv1(BLOCKER_MEDIUM).core_kill_xp.get_value())
	var large := float(_lv1(BLOCKER_LARGE).core_kill_xp.get_value())
	assert_gt(small, 0.0, "a small Dormant Core pays a core bonus")
	assert_almost_eq(medium, 2.0 * small, 1e-6, "medium pays twice small")
	assert_almost_eq(large, 4.0 * small, 1e-6, "large pays four times small")
	assert_almost_eq(float(_lv1(BOARD).core_kill_xp.get_value()), large, 1e-6,
			"an entity's core pays the large Dormant Core tier")


func test_level_caps_strictly_increase() -> void:
	var cap := _cap(1)
	for level in range(1, 21):
		var next := _grow(cap)
		assert_gt(next, cap, "cap(%d) > cap(%d)" % [level + 1, level])
		cap = next


func test_innate_passive_income_takes_ten_turns_to_level() -> void:
	var passive := float(_lv1(BOARD).xp_per_turn.get_value())
	assert_gt(passive, 0.0, "a fresh entity earns passive XP")
	assert_lt(passive, _cap(1) / 10.0, "no level from passive in under ten turns")
