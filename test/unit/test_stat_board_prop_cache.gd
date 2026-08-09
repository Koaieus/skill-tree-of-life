extends GutTest

## #402 — StatBoard caches Stat-typed @export field NAMES per board class
## (`_stat_property_names`), so `collect_formula_edges` / `get_pool_stats` /
## `get_stat_ids` stop paying `get_property_list()` (~11us) once per call.
##
## The regression the cache must not introduce: it is keyed on the DECLARED
## field type (a class fact), not on whether a given instance's field is
## populated (an instance fact). Two boards of the same class disagreeing on
## which fields are null must still enumerate correctly.


func test_two_boards_of_same_class_enumerate_their_own_populated_fields() -> void:
	# Both are NodeStatBoard — same script, so they share one cache entry.
	var a := NodeStatBoard.new()
	var b := NodeStatBoard.new()

	var stake_def: PoolStatDef = load("res://stats_system/defs/stake_level.tres")
	a.stake_level = PoolStat.new()
	a.stake_level.definition = stake_def
	a.stake_level.base_value = stake_def.default_value
	# a.addon_slots left null.

	var addon_def: StatDef = load("res://stats_system/defs/addon_slots.tres")
	b.addon_slots = ScalarStat.new()
	b.addon_slots.definition = addon_def
	b.addon_slots.base_value = addon_def.default_value
	# b.stake_level left null.

	var a_ids := a.get_stat_ids()
	var b_ids := b.get_stat_ids()

	assert_true(a_ids.has(&"stake_level"), "a's populated field is enumerated")
	assert_false(a_ids.has(&"addon_slots"), "a's null field is skipped, not cached-in")

	assert_true(b_ids.has(&"addon_slots"), "b's populated field is enumerated")
	assert_false(b_ids.has(&"stake_level"), "b's null field is skipped, not cached-out")


func test_pool_stats_only_returns_populated_pool_fields_per_instance() -> void:
	var a := NodeStatBoard.new()
	var b := NodeStatBoard.new()

	var stake_def: PoolStatDef = load("res://stats_system/defs/stake_level.tres")
	a.stake_level = PoolStat.new()
	a.stake_level.definition = stake_def

	assert_eq(a.get_pool_stats().size(), 1, "a carries its own stake_level pool")
	assert_eq(b.get_pool_stats().size(), 0, "b's stake_level stays null and is skipped")


func test_cache_is_scoped_per_board_class() -> void:
	# EntityStatBoard and NodeStatBoard are siblings with disjoint field sets;
	# a class-keyed cache must not leak one class's names onto the other.
	var entity_board := EntityStatBoard.new()
	var node_board := NodeStatBoard.new()

	var entity_ids := entity_board.get_stat_ids()
	var node_ids := node_board.get_stat_ids()

	assert_false(entity_ids.has(&"stake_level"), "entity board has no node-only field")
	assert_false(node_ids.has(&"strength"), "node board has no entity-only field")
