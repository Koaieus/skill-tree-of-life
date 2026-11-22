extends GutTest

## Catalyst has no resistance facet: the def is gone from disk and the roster.

const ROSTER := "res://stats_system/stat_def_roster.tres"
const DEF := "res://stats_system/defs/catalyst_resistance.tres"


func test_def_file_is_gone() -> void:
	assert_false(FileAccess.file_exists(DEF), "catalyst_resistance.tres must be deleted")


func test_roster_has_no_catalyst_resistance() -> void:
	var roster: StatDefRoster = load(ROSTER)
	assert_not_null(roster)
	for d in roster.defs:
		assert_ne(d.id, &"catalyst_resistance")
		assert_not_null(d, "roster holds no dangling entry")
