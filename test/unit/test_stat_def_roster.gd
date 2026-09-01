extends GutTest

## [StatRegistry] is the only door onto a [StatDef] at runtime, and it reads
## [StatDefRoster] rather than scanning `stats_system/defs/`.
##
## Why it had to stop scanning: the exporter's default
## `convert_text_resources_to_binary` rewrites every `.tres` into a `.res` +
## `.tres.remap` pair inside the PCK, and `DirAccess` lists what the PCK
## actually contains — so `ends_with(".tres")` matched nothing and the registry
## came up EMPTY in every exported build. Observed 2026-09-01 as 20
## `unknown stat id` / `def missing` warnings on the first frame of a real
## export, against 0 from the same code run from source. #640 found this exact
## shape in [CoreClass.pickable_for]; #597 D13 is the rule it settled
## ("directory scan for editor and test code, authored array for runtime") and
## this is that rule applied to the stat system.
##
## These two tests are the pair that makes the fix stick. The first is the
## drift guard the roster costs — an authored array cannot discover a def
## nobody added to it, so the directory is compared against it here. The second
## pins the mechanism, because a functional test cannot tell "reads the roster"
## from "reads the roster and ALSO scans": on a dev filesystem every `.tres`
## sits right there and both spellings pass.

const _DEFS_DIR := "res://stats_system/defs"
const _ROSTER: StatDefRoster = preload("res://stats_system/stat_def_roster.tres")


func _def_paths_on_disk() -> Array[String]:
	var out: Array[String] = []
	for file in DirAccess.get_files_at(_DEFS_DIR):
		# Tests run from a checkout, never a PCK — the `.tres` filter is correct
		# HERE and wrong in the registry, which is the whole point.
		if file.ends_with(".tres"):
			out.append("%s/%s" % [_DEFS_DIR, file])
	out.sort()
	return out


func test_roster_lists_every_authored_def() -> void:
	var on_disk := _def_paths_on_disk()
	assert_gt(on_disk.size(), 0, "no StatDefs found — is %s right?" % _DEFS_DIR)

	var in_roster: Array[String] = []
	for def in _ROSTER.defs:
		assert_not_null(def, "the roster holds a null entry")
		if def != null:
			in_roster.append(def.resource_path)
	in_roster.sort()

	var missing := on_disk.filter(func(p: String) -> bool: return not in_roster.has(p))
	assert_eq(missing, [] as Array[String],
			"authored but not in stat_def_roster.tres — StatRegistry cannot see these, "
			+ "and only an exported build would show it")

	var stale := in_roster.filter(func(p: String) -> bool: return not on_disk.has(p))
	assert_eq(stale, [] as Array[String], "in the roster but gone from disk")


func test_every_rostered_def_has_a_unique_id() -> void:
	var seen: Dictionary = {}
	for def in _ROSTER.defs:
		if def == null:
			continue
		assert_false(seen.has(def.id),
				"duplicate stat id '%s' — the later entry would silently win" % def.id)
		seen[def.id] = true


## The regression that would actually have caught this. It fails the instant
## the registry touches `DirAccess` again, which is the exact mechanism that
## breaks under the exporter's remap and that no headless test can observe
## from a checkout.
func test_registry_does_not_scan_the_filesystem() -> void:
	var src := FileAccess.get_file_as_string("res://autoload/stat_registry.gd")
	var start := src.find("func _ready(")
	assert_true(start >= 0, "_ready() must still exist in stat_registry.gd")

	var body_end := src.length()
	for marker in ["\nfunc ", "\nstatic func "]:
		var next := src.find(marker, start + 1)
		if next != -1:
			body_end = mini(body_end, next)
	var body := src.substr(start, body_end - start)

	assert_false(body.contains("DirAccess"),
			"StatRegistry._ready() scans the filesystem again — that returns nothing "
			+ "inside a PCK; read StatDefRoster (#597 D13)")


## The registry is an autoload, so this asserts the LIVE singleton, not a fresh
## instance: what every caller actually gets.
func test_live_registry_resolves_every_rostered_id() -> void:
	for def in _ROSTER.defs:
		if def == null:
			continue
		assert_eq(StatRegistry.get_def(def.id), def, "StatRegistry lost '%s'" % def.id)
