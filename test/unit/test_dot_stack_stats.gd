extends GutTest

## The DoT extra-stacks vocabulary: the seven stats resolve with their
## defaults, and every authored status def names exactly the extra-stacks
## stats its family owns — the four DoTs their own plus the umbrella, every
## other status nothing.

const _STATUS_DIR := "res://effects/status/"
const _DOT_FAMILIES: Array[StringName] = [&"poison", &"corruption", &"curse", &"wither"]
const _DEFAULTS := {
	&"poison_stacks_per_hit": 0.0,
	&"corruption_stacks_per_hit": 0.0,
	&"curse_stacks_per_hit": 0.0,
	&"wither_stacks_per_hit": 0.0,
	&"dot_stacks_per_hit": 0.0,
	&"blindness_potency": 1.0,
	&"blindness_resistance": 0.0,
}


func test_the_seven_stats_resolve_through_the_registry_with_their_defaults() -> void:
	var board := (load("res://entity/default_entity_board.tres") as EntityStatBoard).duplicate(true) as EntityStatBoard
	for id: StringName in _DEFAULTS:
		var def := StatRegistry.get_def(id)
		assert_not_null(def, "%s is registered" % id)
		if def == null:
			continue
		assert_almost_eq(float(def.default_value), float(_DEFAULTS[id]), 0.0001, "%s default" % id)
		assert_not_null(board.get_stat(id), "%s has an instance on the default board" % id)
		assert_almost_eq(float(board.get_value(id)), float(_DEFAULTS[id]), 0.0001, "%s board value" % id)


func test_every_status_def_names_its_familys_extra_stacks_stats() -> void:
	var seen := 0
	for file in DirAccess.get_files_at(_STATUS_DIR):
		if not file.ends_with(".tres"):
			continue
		var def := load(_STATUS_DIR + file) as StatusDef
		if def == null:
			continue
		seen += 1
		var expected: Array[StringName] = []
		if def.id in _DOT_FAMILIES:
			expected = [StringName("%s_stacks_per_hit" % def.id), &"dot_stacks_per_hit"]
		assert_eq(def.extra_stacks_stat_ids, expected, "%s extra_stacks_stat_ids" % def.id)
	assert_gt(seen, 5, "the sweep found the authored defs")
