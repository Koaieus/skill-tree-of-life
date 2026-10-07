extends GutTest

## The stacks-per-hit vocabulary: the seven stats resolve with their
## defaults, and every authored status def names the one stacks stat it folds
## through — each DoT its family stat, blindness its own, every other status
## none.

const _STATUS_DIR := "res://effects/status/"
const _DOT_FAMILIES: Array[StringName] = [&"poison", &"corruption", &"curse", &"wither"]
const _DEFAULTS := {
	&"poison_stacks_per_hit": 0.0,
	&"corruption_stacks_per_hit": 0.0,
	&"curse_stacks_per_hit": 0.0,
	&"wither_stacks_per_hit": 0.0,
	&"dot_stacks_per_hit": 0.0,
	&"blindness_stacks_per_hit": 0.0,
	&"blindness_resistance": 0.0,
	&"weakness_stacks_per_hit": 1.0,
	&"greed_stacks_per_hit": 1.0,
	&"bleeding_stacks_per_hit": 1.0,
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


func test_every_status_def_names_its_familys_stacks_stat() -> void:
	var seen := 0
	for file in DirAccess.get_files_at(_STATUS_DIR):
		if not file.ends_with(".tres"):
			continue
		var def := load(_STATUS_DIR + file) as StatusDef
		if def == null:
			continue
		seen += 1
		var expected := &""
		if def.id in _DOT_FAMILIES or def.id in [&"blindness", &"weakness", &"greed", &"hex", &"bleeding"]:
			# The umbrella folds into each DoT family stat as its parent (ADR 0029); blindness, weakness, greed and hex have none.
			expected = StringName("%s_stacks_per_hit" % def.id)
		assert_eq(def.stacks_stat_id, expected, "%s stacks_stat_id" % def.id)
	assert_gt(seen, 5, "the sweep found the authored defs")
