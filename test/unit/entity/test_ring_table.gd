extends GutTest
## The inner ring's rules come from sampling its authored Graph scene once:
## 30 cells + Core, PoE adjacency gating, and no live ring left in the tree.

const _RING_PATH := "res://entity/ring/aspect_ring.tscn"


func _system() -> RingSystem:
	var sys := RingSystem.new()
	sys.ring_scene = load(_RING_PATH)
	add_child_autofree(sys)
	return sys


func test_the_default_ring_is_six_sectors_of_five_cells() -> void:
	var table := _system().table()
	assert_not_null(table, "RingSystem sampled a table")
	if table == null:
		return
	var names := table.cells()
	assert_eq(names.size(), 30, "30 cells, Core excluded")
	assert_false(names.has(table.centre()), "the centre is never a buyable cell")
	var per_sector := {}
	for n in names:
		var c := table.cell(n)
		assert_not_null(c.sector, "%s has a sector" % n)
		if c.sector == null:
			continue
		var tiers: Array = per_sector.get_or_add(c.sector.id, [])
		tiers.append(c.tier)
		assert_eq(c.aspect == null, c.tier == 0, "%s: only a keystone has no aspect" % n)
		assert_gt(c.grants.size(), 0, "%s grants something" % n)
	assert_eq(per_sector.size(), 6, "six sectors")
	for id in per_sector:
		var tiers: Array = per_sector[id]
		tiers.sort()
		assert_eq(tiers, [0, 1, 1, 2, 2], "sector %s = keystone + 2 T1 + 2 T2" % id)


func test_every_cell_but_core_carries_a_ring_cell_addon_and_names_are_unique() -> void:
	var inst: Node = (load(_RING_PATH) as PackedScene).instantiate()
	var seen := {}
	var cells := 0
	for n: Node in inst.get_node("Nodes").get_children():
		assert_false(seen.has(n.name), "unique name %s" % n.name)
		seen[n.name] = true
		var has_addon := false
		for c in n.get_children():
			has_addon = has_addon or c is RingCellAddon
		if n.name == &"Core":
			assert_false(has_addon, "Core carries no cell addon")
		else:
			cells += 1
			assert_true(has_addon, "%s carries a RingCellAddon" % n.name)
	assert_eq(cells, 30)
	inst.free()


func test_can_buy_is_adjacency_to_core_or_a_bought_cell() -> void:
	var table := _system().table()
	if table == null:
		fail_test("no table")
		return
	var none: Array[StringName] = []
	var t1: Array[StringName] = [&"BleedingT1"]
	assert_true(table.can_buy(none, &"BleedingT1"), "a T1 touches Core")
	assert_false(table.can_buy(none, &"BleedingT2"), "a T2 waits for its T1")
	assert_true(table.can_buy(t1, &"BleedingT2"), "its T1 bought opens the T2")
	assert_false(table.can_buy(t1, &"BleedingT1"), "a spent cell is not buyable")
	assert_false(table.can_buy(none, table.centre()), "Core is never bought")


func test_the_sampled_ring_instance_is_freed() -> void:
	var sys := _system()
	assert_eq(sys.get_child_count(), 0, "no live ring Graph left under RingSystem")
