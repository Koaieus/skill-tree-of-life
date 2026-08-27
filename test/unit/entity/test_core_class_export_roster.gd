extends GutTest

## #640 — CoreClass.pickable_for() is the one RUNTIME caller of CoreClass
## discovery (lobby_screen.gd's per-slot dropdown, #618). A directory scan
## silently returns [] in an exported build: the exporter's default
## `convert_text_resources_to_binary = true` rewrites every `.tres` into a
## `.res` + `.tres.remap` pair inside the PCK, and `DirAccess.get_files_at()`
## lists what the PCK actually contains — never what `load()`'s remap-following
## would suggest. Confirmed 2026-08-27 via a real `--export-pack` run in a
## filesystem isolated from the source tree (no project.godot in cwd,
## `--main-pack` only): the scan of `entity/core/` saw
## `["balanced_core.tres.remap", "basic_enemy_core.tres.remap", ...]`, matched
## none of them against `.ends_with(".tres")`, and `pickable_for()` returned an
## empty array for both slot kinds.
##
## Per #597 D13 ("directory scan for editor and test code, authored array for
## runtime"), the fix moves ONLY the runtime path onto [CoreClassRoster] — a
## hard `ExtResource` dependency edge, immune to the remap. [method
## CoreClass.load_all] stays a scan: test_stat_dependency_graph.gd's #322 DAG
## check needs a newly authored, unreferenced CoreClass to still surface,
## which an authored array could never guarantee.

const _ROSTER: CoreClassRoster = preload("res://entity/core/core_class_roster.tres")


## The regression that would actually have caught #640. A functional test
## can't tell "reads the roster" apart from "reads the roster, and ALSO still
## scans" — every `.tres` sits right there on disk in the editor either way.
## Only a real export (or reading the source) can tell the difference, and
## export templates aren't installed in this environment (see the issue for
## why). This is the cheap proxy: it fails the instant `pickable_for` touches
## `DirAccess` again, which is exactly the mechanism that breaks under the
## exporter's remap.
func test_pickable_for_does_not_scan_the_filesystem() -> void:
	var src := FileAccess.get_file_as_string("res://entity/core/core_class.gd")
	var start := src.find("func pickable_for(")
	assert_true(start >= 0, "pickable_for() must still exist in core_class.gd")

	var body_end := src.length()
	for marker in ["\nfunc ", "\nstatic func "]:
		var idx := src.find(marker, start + 1)
		if idx != -1 and idx < body_end:
			body_end = idx
	var body := src.substr(start, body_end - start)

	assert_false(body.contains("DirAccess"),
			"pickable_for() must resolve through CoreClassRoster, not a directory scan — " +
			"a scan is exactly what returns [] under the exporter's .tres->.res remap (#640)")


func test_roster_is_authored_as_a_core_class_roster() -> void:
	assert_true(_ROSTER is CoreClassRoster)
	assert_gt(_ROSTER.classes.size(), 0, "the roster must actually list something")


## Every class load_all()'s scan would find with a nonzero pickable mask must
## also be in the roster — the roster's whole job is to mirror the pickable
## subset of the scan into a hard dependency edge. Drift here means a newly
## authored pickable core silently vanishes from every dropdown again, just
## from a forgotten roster entry instead of the export remap.
func test_every_pickable_scanned_class_is_in_the_roster() -> void:
	for core in CoreClass.load_all():
		if core.pickable_in != 0:
			assert_true(_ROSTER.classes.has(core),
					"%s is pickable but missing from core_class_roster.tres" % core.resource_path)


func test_pickable_for_matches_roster_filtered_by_mask() -> void:
	for bit in [CoreClass.PICKABLE_PLAYER, CoreClass.PICKABLE_AI]:
		var expected: Array = []
		for core in _ROSTER.classes:
			if core.is_pickable_in(bit):
				expected.append(core)
		assert_eq(CoreClass.pickable_for(bit), expected)
