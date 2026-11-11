extends GutTest

## The element roster mirrors `elements/defs/` and each Element holds what
## #1793 authors (`docs/domain/elements.md`): facets on the element identity,
## ascending bands, the travel verbs, light and the decay knobs.

const DEFS_DIR := "res://elements/defs/"
const _POISON := preload("res://effects/status/poison.tres")
## element → [terrain id, school id, primed band id, overflow band id or &"", verb]
const _SHAPE := {
	&"fire": [&"heat", &"strength", &"burning", &"", ElementBand.Travel.SPREADS],
	&"ice": [&"cold", &"dexterity", &"frozen", &"deep_freeze", ElementBand.Travel.ENDS],
	&"lightning": [&"charge", &"intelligence", &"shocked", &"", ElementBand.Travel.CONDUCTS],
}


func _elements() -> Array[Element]:
	var out: Array[Element] = []
	var roster := ElementRoster.shared()
	assert_not_null(roster, "element_roster.tres loads")
	if roster != null:
		out = roster.elements
	return out


func test_roster_lists_every_def_in_the_directory() -> void:
	var listed := {}
	for element in _elements():
		assert_not_null(element)
		listed[element.resource_path] = true
	var on_disk := PackedStringArray()
	for file in DirAccess.get_files_at(DEFS_DIR):
		if file.ends_with(".tres"):
			on_disk.append(DEFS_DIR + file)
	assert_eq(on_disk.size(), 3, "three elements authored")
	for path in on_disk:
		assert_true(listed.has(path), "%s is on the roster" % path)
	assert_eq(listed.size(), on_disk.size(), "roster lists nothing else")


func test_ids_unique_and_lookups_resolve() -> void:
	var roster := ElementRoster.shared()
	assert_not_null(roster)
	if roster == null:
		return
	var seen := {}
	for element in roster.elements:
		var id := element.id()
		assert_false(seen.has(id), "id %s unique" % id)
		seen[id] = true
		assert_eq(roster.by_id(id), element, "by_id(%s)" % id)
		assert_not_null(element.stat, "%s has a count stat" % id)
		if element.stat != null:
			assert_eq(roster.for_stat(element.stat.id), element, "for_stat(%s)" % element.stat.id)
		assert_not_null(element.terrain, "%s has a terrain stack" % id)
		assert_eq(roster.for_status(element.terrain), element, "for_status(terrain of %s)" % id)
		for mover in element.movers:
			assert_eq(roster.for_status(mover), element, "for_status(mover of %s)" % id)
	assert_eq(seen.size(), _SHAPE.size(), "fire, ice, lightning")
	assert_null(roster.by_id(&"no_such_element"))
	assert_null(roster.for_stat(&"no_such_stat"))
	assert_null(roster.for_status(_POISON), "an aspect's status is no member")
	assert_null(roster.for_status(null))


func test_every_facet_carries_the_element_identity() -> void:
	for element in _elements():
		var id := element.id()
		assert_eq(element.identity.kind, Identity.Kind.ELEMENT, "%s is Kind.ELEMENT" % id)
		assert_eq(element.stat.identity, element.identity, "%s: count stat identity" % id)
		assert_eq(element.stat.role, StatDef.Role.COUNT, "%s: count stat is the COUNT facet" % id)
		assert_eq(element.stat.id, StringName("%s_element" % id), "%s: count stat id" % id)
		assert_eq(element.stat.display_name, "%s attunement" % element.identity.noun, "%s: count display" % id)
		assert_true(element.stat.parent_ids.is_empty(), "%s: count has no family parent" % id)
		assert_eq(element.terrain.identity.kind, Identity.Kind.ELEMENT, "%s: terrain is Kind.ELEMENT" % id)
		assert_eq(element.terrain.id, _SHAPE[id][0], "%s: terrain stack" % id)
		assert_eq(element.school.kind, Identity.Kind.ATTRIBUTE, "%s: school is an attribute" % id)
		assert_eq(element.school.id, _SHAPE[id][1], "%s: school" % id)
		for band in element.bands:
			if band.identity != null:
				assert_eq(band.identity.kind, Identity.Kind.ELEMENT, "%s: band identity kind" % id)


func test_bands_ascend_and_only_the_last_is_at_cap() -> void:
	for element in _elements():
		var id := element.id()
		var bands := element.bands
		assert_eq(bands.size(), 2, "%s: a primed band and an overflow band" % id)
		for i in bands.size():
			assert_gte(bands[i].threshold_multiple, 1, "%s band %d multiple" % [id, i])
			if i > 0:
				assert_gte(bands[i].threshold_multiple, bands[i - 1].threshold_multiple,
						"%s band %d ascends" % [id, i])
			assert_eq(bands[i].at_cap, i == bands.size() - 1, "%s band %d at_cap only last" % [id, i])
		if not bands.is_empty():
			assert_eq(bands[0].threshold_multiple, 1, "%s primes at ×1" % id)


func test_no_go_off_or_admits_is_authored_yet() -> void:
	for element in _elements():
		for band in element.bands:
			assert_null(band.go_off, "%s: go_off lands with #1799/#1800/#1806" % element.id())
			assert_null(band.admits, "%s: admits lands with #1807" % element.id())


## The overflow band keeps its primed band's verb (lead call, tentative: this
## test alone moves if the owner rules otherwise).
func test_travel_verbs_and_band_identities() -> void:
	for element in _elements():
		var id := element.id()
		if element.bands.size() < 2:
			continue
		var primed := element.bands[0]
		var overflow := element.bands[1]
		assert_eq(primed.identity.id if primed.identity else &"", _SHAPE[id][2], "%s primed band" % id)
		assert_eq(overflow.identity.id if overflow.identity else &"", _SHAPE[id][3], "%s overflow band" % id)
		assert_eq(primed.travel, _SHAPE[id][4], "%s primed verb" % id)
		assert_eq(overflow.travel, primed.travel, "%s overflow keeps the primed verb" % id)


func test_burning_lights_and_no_ice_or_lightning_band_does() -> void:
	var roster := ElementRoster.shared()
	assert_not_null(roster)
	if roster == null:
		return
	assert_true(roster.by_id(&"fire").bands[0].light, "Burning is a light source")
	for id in [&"ice", &"lightning"]:
		for band in roster.by_id(id).bands:
			assert_false(band.light, "%s band lights nothing" % id)


func test_decay_rates() -> void:
	for element in _elements():
		var id := element.id()
		assert_eq(element.decay_per_world_turn, 1, "%s decays 1 below its first band" % id)
		if element.bands.size() < 2:
			continue
		assert_gte(element.bands[1].decay_per_world_turn, element.bands[0].decay_per_world_turn,
				"%s: overflow decays at least as fast as its primed band" % id)
