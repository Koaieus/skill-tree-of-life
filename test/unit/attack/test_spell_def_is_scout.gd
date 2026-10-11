extends GutTest

## [method SpellDef.is_scout]: exactly the defs whose affinities land
## `scouted` answer true — every authored def under `attack/spell/defs/`.

const DEFS_DIR := "res://attack/spell/defs/"
const SCOUTS := [&"scout_line", &"eagle_eye"]


func test_only_the_scout_spells_are_scouts() -> void:
	var seen := 0
	for file in DirAccess.get_files_at(DEFS_DIR):
		if not file.ends_with(".tres"):
			continue
		var def := load(DEFS_DIR + file) as SpellDef
		if def == null:
			continue
		seen += 1
		assert_eq(def.is_scout(), SCOUTS.has(def.id), "%s.is_scout()" % def.id)
	assert_gt(seen, SCOUTS.size(), "the sweep read the defs folder")


func test_an_affinity_with_no_status_is_not_a_scout() -> void:
	var def := SpellDef.new()
	def.affinities = [SpellAffinity.new()]
	assert_false(def.is_scout())
