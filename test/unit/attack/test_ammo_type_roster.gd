extends GutTest

## The ammo roster is the one place the volley order and the arrow set live:
## it covers every authored type, ids are the agreed eight, and each special
## mints its own `<concept>_aspect`.

const _ROSTER := preload("res://attack/ammo/ammo_type_roster.tres")
const _STATS := preload("res://stats_system/stat_def_roster.tres")
const _DIR := "res://attack/ammo/types"
const _IDS: Array[StringName] = [&"arrow", &"poison", &"scout", &"corruption",
		&"curse", &"wither", &"armor_break", &"blindness"]


func test_roster_covers_every_type_on_disk() -> void:
	var on_disk: Array[String] = []
	for file in DirAccess.get_files_at(_DIR):
		if file.ends_with(".tres"):
			on_disk.append("%s/%s" % [_DIR, file])
	var in_roster: Array[String] = []
	for t in _ROSTER.types:
		in_roster.append(t.resource_path)
	on_disk.sort()
	in_roster.sort()
	assert_eq(in_roster, on_disk, "roster and types/ directory agree")


func test_ids_are_exactly_the_agreed_set() -> void:
	var ids: Array[StringName] = []
	for t in _ROSTER.types:
		ids.append(t.id)
	ids.sort()
	var want := _IDS.duplicate()
	want.sort()
	assert_eq(ids, want)


func test_per_reload_stats_are_distinct_and_aspects_exist() -> void:
	var stat_ids: Dictionary = {}
	for d in _STATS.defs:
		stat_ids[d.id] = true
	var seen: Dictionary = {}
	for t in _ROSTER.types:
		assert_false(seen.has(t.per_reload_stat_id), "duplicate stat %s" % t.per_reload_stat_id)
		seen[t.per_reload_stat_id] = true
		if t.id == AmmoTypeRoster.BASE_ID:
			continue
		assert_eq(t.per_reload_stat_id, StringName("%s_aspect" % t.id), "%s mints its aspect" % t.id)
		assert_true(stat_ids.has(t.per_reload_stat_id), "%s on the StatDefRoster" % t.per_reload_stat_id)



func test_statused_specials_order_below_base_and_scout_stays_last() -> void:
	var base := _ROSTER.base_type()
	for t in _ROSTER.types:
		if t.id == AmmoTypeRoster.BASE_ID or t.status_def == null:
			continue
		assert_eq((t.status_def as StatusDef).id, t.id, "%s carries its own status" % t.id)
		assert_lt(t.order, base.order, "%s volleys before the base arrow" % t.id)
	assert_eq(_ROSTER.sorted().back().id, &"scout")


func test_status_for_blindness_arrow_carries_the_def_at_authored_power() -> void:
	var type := _ROSTER.by_id(&"blindness")
	var hit := RangedDamageFormula.compute(null, null, null, type)
	var status := RangedDamageFormula.status_for(hit)
	assert_not_null(status)
	assert_eq(status.def.resource_path, "res://effects/status/blindness.tres")
	assert_eq(status.power, type.status_power)
