extends GutTest

## #511 / #1026 — [member SpellDef.id] is the wire name of a spell, so it has to
## be real on every authored def and unique across them, and the authored
## `spell_catalog.tres` has to list every def on disk. A duplicate, a blank or a
## missing entry breaks [MagicAttackPlan]'s wire form with no error at the
## break: the peer simply casts a different spell, or none.

const _PATH := "res://attack/spell/spell_catalog.tres"
const _DEFS := "res://attack/spell/defs"


func _catalog() -> Variant:
	return load(_PATH) if ResourceLoader.exists(_PATH) else null


func _spells() -> Array:
	var catalog: Variant = _catalog()
	return catalog.spells if catalog != null else []


func test_the_catalog_is_an_authored_resource() -> void:
	var catalog: Variant = _catalog()
	assert_not_null(catalog, "%s must exist" % _PATH)
	if catalog != null:
		assert_true(catalog is Resource, "the catalog is an authored Resource, not a const list")


func test_every_authored_spell_carries_an_id() -> void:
	for spell in _spells():
		assert_ne(spell.id, &"", "%s has no id — it cannot cross a wire" % spell.resource_path)


func test_spell_ids_are_unique() -> void:
	var seen: Dictionary = {}
	for spell in _spells():
		assert_false(seen.has(spell.id),
				"duplicate spell id '%s' (%s) — the wire form would resolve to the wrong def"
				% [spell.id, spell.resource_path])
		seen[spell.id] = true


func test_the_catalog_covers_every_authored_def() -> void:
	# A def added to `attack/spell/defs/` but not to the catalog is
	# unreferenceable over the wire, and nothing else would notice.
	var listed: Array[String] = []
	for spell in _spells():
		listed.append(spell.resource_path)
	var on_disk: Array[String] = []
	for file in ResourceLoader.list_directory(_DEFS):
		if file.get_extension() == "tres":
			on_disk.append(_DEFS.path_join(file))
	assert_gt(on_disk.size(), 0, "no defs found on disk")
	for path in on_disk:
		assert_has(listed, path, "%s is authored but not in the catalog" % path)
	assert_eq(listed.size(), on_disk.size(), "catalog holds %d, disk holds %d"
			% [listed.size(), on_disk.size()])


func test_by_id_returns_the_authored_resource_itself() -> void:
	var catalog: Variant = _catalog()
	assert_not_null(catalog)
	if catalog == null:
		return
	for spell in _spells():
		assert_same(catalog.by_id(spell.id), spell,
				"by_id must return the SAME resource, so identity checks keep working")
		assert_same(catalog.by_id(spell.id), load(spell.resource_path),
				"the resource cache shares the def with a plain load() of its path")


func test_by_id_answers_null_for_an_unknown_or_blank_id() -> void:
	var catalog: Variant = _catalog()
	assert_not_null(catalog)
	if catalog == null:
		return
	assert_null(catalog.by_id(&""), "a blank id is 'no spell', not the first one")
	assert_null(catalog.by_id(&"not_a_spell"))
