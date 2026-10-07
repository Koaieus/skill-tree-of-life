extends GutTest

## The ammo roster is the one place the volley order and the arrow set live:
## it covers every authored type, ids are the agreed eight, and each special
## mints its own `<concept>_aspect`.

const _ROSTER := preload("res://attack/ammo/ammo_type_roster.tres")
const _STATS := preload("res://stats_system/stat_def_roster.tres")
const _DIR := "res://attack/ammo/types"
const _IDS: Array[StringName] = [&"arrow", &"poison", &"scout", &"corruption",
		&"curse", &"wither", &"armor_break", &"blindness", &"greed", &"weakness", &"bleeding", &"hex"]


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
		if t.id == AmmoTypeRoster.BASE_ID or t.is_scout() or t.first_status_def() == null:
			continue
		assert_eq(t.first_status_def().id, t.id, "%s carries its own status" % t.id)
		assert_lt(t.order, base.order, "%s volleys before the base arrow" % t.id)
	assert_eq(_ROSTER.sorted().back().id, &"scout")


## The flare: the rider is splashed. A lone node has no neighbours to reach,
## so the target's own rider is the whole set here (the reach is
## test_splash_effect.gd's).
func test_riders_for_blindness_arrow_carries_the_def_at_authored_power() -> void:
	var type := _ROSTER.by_id(&"blindness")
	var splash: Variant = type.on_hit_effects[0]
	assert_true(splash is SplashEffect, "blindness flares (#1390)")
	var target: SkillNode = autofree(SkillNode.new())
	var hit := RangedDamageFormula.compute(null, null, target, type)
	var riders := RangedDamageFormula.riders_for(hit)
	assert_eq(riders.size(), 1)
	var status := riders[0] as StatusInstance
	assert_not_null(status)
	assert_eq(status.def.resource_path, "res://effects/status/blindness.tres")
	assert_eq(status.power, (splash.inner as ApplyStatusEffect).power)


## Every statused type flies its own inherited scene of the base status arrow,
## so a bespoke look lands on exactly one type.
func test_statused_types_fly_their_own_status_arrow_scene() -> void:
	const BASE_SCENE := "res://ui/vfx/projectile/visual/status_arrow.tscn"
	var seen: Dictionary = {}
	for t in _ROSTER.types:
		if t.first_status_def() == null:
			continue
		var scene: PackedScene = t.visual_scene
		assert_not_null(scene, "%s has a visual_scene" % t.id)
		if scene == null:
			continue
		var base := scene.get_state().get_node_instance(0)
		assert_eq(base.resource_path if base != null else "", BASE_SCENE, "%s inherits the status arrow" % t.id)
		assert_false(seen.has(scene.resource_path), "%s shares %s" % [t.id, scene.resource_path])
		seen[scene.resource_path] = true
