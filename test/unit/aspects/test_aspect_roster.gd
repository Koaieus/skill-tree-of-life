extends GutTest

## The aspect roster mirrors `aspects/defs/` and every facet agrees with its
## Aspect's identity (ADR 0046) — the matrix row as data.

const DEFS_DIR := "res://aspects/defs/"
const STAT_DEFS_DIR := "res://stats_system/defs/"


func _roster() -> AspectRoster:
	return AspectRoster.shared()


func _tres_in(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file in DirAccess.get_files_at(dir_path):
		if file.ends_with(".tres"):
			out.append(dir_path + file)
	return out


func test_roster_lists_every_def_in_the_directory() -> void:
	var roster := _roster()
	assert_not_null(roster, "aspect_roster.tres loads")
	if roster == null:
		return
	var listed := {}
	for aspect in roster.aspects:
		assert_not_null(aspect)
		listed[aspect.resource_path] = true
	var on_disk := _tres_in(DEFS_DIR)
	assert_eq(on_disk.size(), 12, "twelve concept aspects authored")
	for path in on_disk:
		assert_true(listed.has(path), "%s is on the roster" % path)
	assert_eq(roster.aspects.size(), on_disk.size(), "roster lists nothing else")


func test_ids_unique_and_lookups_resolve() -> void:
	var roster := _roster()
	assert_not_null(roster)
	if roster == null:
		return
	var seen := {}
	for aspect in roster.aspects:
		assert_not_null(aspect.identity, "%s has an identity" % aspect.resource_path)
		if aspect.identity == null:
			continue
		var id := aspect.id()
		assert_false(seen.has(id), "id %s unique" % id)
		seen[id] = true
		assert_eq(roster.by_id(id), aspect, "by_id(%s)" % id)
		assert_not_null(aspect.stat, "%s has a stat" % id)
		if aspect.stat != null:
			assert_eq(roster.for_stat(aspect.stat.id), aspect, "for_stat(%s)" % aspect.stat.id)
	assert_null(roster.by_id(&"no_such_aspect"))
	assert_null(roster.for_stat(&"no_such_stat"))


func test_every_facet_carries_the_aspect_identity() -> void:
	var roster := _roster()
	assert_not_null(roster)
	if roster == null:
		return
	assert_false(roster.aspects.is_empty(), "roster has aspects")
	for aspect in roster.aspects:
		var identity := aspect.identity
		var id := aspect.id()
		assert_eq(aspect.stat.identity, identity, "%s: stat identity" % id)
		if aspect.status != null:
			assert_eq(aspect.status.identity, identity, "%s: status identity" % id)
		if aspect.ammo != null and aspect.ammo.first_status_def() != null:
			assert_eq(aspect.ammo.first_status_def().identity, identity, "%s: ammo status identity" % id)
		for spell in aspect.spells:
			assert_not_null(spell, "%s: spell slot filled" % id)
			if spell == null:
				continue
			for effect in spell.on_hit_effects:
				var apply := effect as ApplyStatusEffect
				if apply == null or apply.def == null:
					continue
				assert_eq(apply.def.identity, identity,
					"%s: spell %s applies %s" % [id, spell.id, apply.def.resource_path])


func test_aspects_family_children_are_exactly_the_rostered_stats() -> void:
	var roster := _roster()
	assert_not_null(roster)
	if roster == null:
		return
	var children := {}
	for path in _tres_in(STAT_DEFS_DIR):
		var def := load(path) as StatDef
		if def != null and def.parent_ids.has(&"aspects"):
			children[def.id] = true
	var rostered := {}
	for aspect in roster.aspects:
		if aspect.stat != null:
			rostered[aspect.stat.id] = true
	assert_false(children.is_empty(), "the aspects family has children")
	for stat_id in children:
		assert_true(rostered.has(stat_id), "%s is some Aspect's stat" % stat_id)
	for stat_id in rostered:
		assert_true(children.has(stat_id), "%s is a child of aspects" % stat_id)
