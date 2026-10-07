extends GutTest

## [StatusRoster] is the runtime door onto a [StatusDef] by concept; an authored
## array cannot discover a status nobody added, so the directory is compared
## against it here (the [StatDefRoster] drift guard).

const _DIR := "res://effects/status"


func test_roster_lists_every_authored_status() -> void:
	var on_disk: Array[String] = []
	for file in DirAccess.get_files_at(_DIR):
		if file.ends_with(".tres"):
			on_disk.append("%s/%s" % [_DIR, file])
	on_disk.sort()
	var listed: Array[String] = []
	for status in StatusRoster.shared().statuses:
		listed.append(status.resource_path)
	listed.sort()
	assert_eq(listed, on_disk, "effects/status_roster.tres must list every effects/status/*.tres")


func test_by_concept_resolves_through_identity() -> void:
	var roster := StatusRoster.shared()
	assert_eq(roster.by_concept(&"poison"), load("res://effects/status/poison.tres"))
	assert_eq(roster.by_concept(&"hex"), load("res://effects/status/hexed.tres"),
			"keyed on the concept, not the file name")
	assert_null(roster.by_concept(&"no_such_concept"))
