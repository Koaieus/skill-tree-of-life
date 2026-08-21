extends GutTest

## #511 — [member SpellDef.id] is the wire name of a spell, so it has to be
## real on every authored def and unique across them. A duplicate or a blank
## breaks [MagicAttackPlan]'s wire form with no error at the break: the peer
## simply casts a different spell, or none.


func test_every_authored_spell_carries_an_id() -> void:
	for spell in SpellCatalog.ALL:
		assert_ne(spell.id, &"", "%s has no id — it cannot cross a wire" % spell.name)


func test_spell_ids_are_unique() -> void:
	var seen: Dictionary = {}
	for spell in SpellCatalog.ALL:
		assert_false(seen.has(spell.id),
				"duplicate spell id '%s' (%s) — the wire form would resolve to the wrong def"
				% [spell.id, spell.name])
		seen[spell.id] = true


func test_the_catalog_covers_every_authored_def() -> void:
	# A def added to `attack/spell/defs/` but not to the catalog is
	# unreferenceable over the wire, and nothing else would notice.
	var on_disk: Array[String] = []
	for file in DirAccess.get_files_at("res://attack/spell/defs"):
		if file.ends_with(".tres"):
			on_disk.append(file)
	assert_eq(SpellCatalog.ALL.size(), on_disk.size(),
			"catalog holds %d, disk holds %d: %s"
			% [SpellCatalog.ALL.size(), on_disk.size(), on_disk])


func test_by_id_returns_the_authored_resource_itself() -> void:
	for spell in SpellCatalog.ALL:
		assert_eq(SpellCatalog.by_id(spell.id), spell,
				"by_id must return the SAME resource, so identity checks keep working")


func test_by_id_answers_null_for_an_unknown_or_blank_id() -> void:
	assert_null(SpellCatalog.by_id(&""), "a blank id is 'no spell', not the first one")
	assert_null(SpellCatalog.by_id(&"not_a_spell"))
