extends GutTest
## RingSilhouette: the hero card's read-only wheel entries and rim sector,
## built from the shipped ring's RingTable and a `ring_spent` list.

var _table: RingTable


func before_each() -> void:
	var system: RingSystem = add_child_autofree(RingSystem.new())
	_table = system.table()


func _value_of(entries: Array[AspectWheelEntry], id: StringName) -> int:
	for e in entries:
		if e.id == id:
			return e.value
	fail_test("no entry for %s" % id)
	return -1


func _spent(names: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for n in names:
		out.append(StringName(n))
	return out


func test_no_cells_gives_one_empty_entry_per_aspect() -> void:
	var entries := RingSilhouette.entries(_table, _spent([]))
	assert_eq(entries.size(), 12)
	var ids := {}
	for e in entries:
		assert_eq(e.value, 0, "%s starts empty" % e.id)
		assert_not_null(e.identity, "%s carries its identity" % e.id)
		assert_false(e.hub_text.is_empty(), "%s names itself on hover" % e.id)
		ids[e.id] = true
	assert_eq(ids.size(), 12, "one entry per distinct aspect")


func test_entries_follow_ring_order() -> void:
	var entries := RingSilhouette.entries(_table, _spent([]))
	assert_eq(entries[0].id, &"bleeding")
	assert_eq(entries[1].id, &"weakness")


func test_bought_tiers_fill_their_aspect() -> void:
	var t1 := RingSilhouette.entries(_table, _spent(["BleedingT1"]))
	var both := RingSilhouette.entries(_table, _spent(["BleedingT1", "BleedingT2"]))
	assert_gt(_value_of(both, &"bleeding"), _value_of(both, &"weakness"))
	assert_gt(_value_of(both, &"bleeding"), _value_of(t1, &"bleeding"), "T2 fuller than T1")
	assert_gt(_value_of(t1, &"bleeding"), 0)


func test_dominant_sector_is_none_with_nothing_bought() -> void:
	assert_null(RingSilhouette.dominant_sector(_table, _spent([])))


func test_dominant_sector_has_most_bought_cells() -> void:
	var s := RingSilhouette.dominant_sector(_table, _spent(["BleedingT1", "PoisonT1", "PoisonT2"]))
	assert_not_null(s)
	assert_eq(s.id if s != null else &"", &"dexterity")


func test_dominant_sector_tie_breaks_str_dex_int_con_per_wis() -> void:
	var s := RingSilhouette.dominant_sector(_table, _spent(["PoisonT1", "BleedingT1"]))
	assert_eq(s.id if s != null else &"", &"strength")
	s = RingSilhouette.dominant_sector(_table, _spent(["CorruptionT1", "WitherT1", "ScoutT1"]))
	assert_eq(s.id if s != null else &"", &"constitution", "CON before PER before WIS")
