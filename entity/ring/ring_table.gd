class_name RingTable
extends RefCounted
## The inner ring's rules, sampled ONCE from its authored Graph scene by
## [RingSystem] (see `docs/adr/0064-*`): per cell name, its aspect, sector,
## tier, cost, grants and neighbour names, plus the centre's name. Gating is
## PoE adjacency — a cell is buyable iff unspent and an edge links it to the
## centre or to a cell already bought. Affordability is the caller's.


## One sampled cell. `grants` are the node's runtime `modifiers` — shared
## instances; a buyer duplicates before granting.
class Cell extends RefCounted:
	var name: StringName
	var aspect: Resource  ## an [Aspect]; null on a keystone
	var sector: Identity
	var tier: int
	var cost: int
	var grants: Array[StatModifier] = []
	var neighbours: Array[StringName] = []


var _cells: Dictionary[StringName, Cell] = {}
var _order: Array[StringName] = []
var _centre: StringName = &""


## Read `graph` (an in-tree ring instance) into a table. The node named
## `centre_name` is adjacency only: never a cell, never bought. A cell without
## a [RingCellAddon] is skipped, and an illegal entity grant is rejected the
## way [method SkillNode._rejects_entity_grant] does — both loudly.
static func sample(graph: Graph, centre_name: StringName = &"Core") -> RingTable:
	var t := RingTable.new()
	t._centre = centre_name
	for node in graph.get_skill_nodes():
		if node.name == centre_name:
			continue
		var addon := _addon_of(node)
		if addon == null:
			push_error("RingTable: '%s' carries no RingCellAddon; skipped" % node.name)
			continue
		var c := Cell.new()
		c.name = node.name
		c.aspect = addon.aspect
		c.sector = addon.sector
		c.tier = addon.tier
		c.cost = addon.cost
		for nb in graph.get_neighbours(node):
			c.neighbours.append(StringName(nb.name))
		for m in node.modifiers:
			var bad := StatRegistry.illegal_leaf(m, false)
			if bad != &"":
				push_error("RingTable: '%s' may not grant '%s' to an entity" % [node.name, bad])
				continue
			c.grants.append(m)
		t._cells[c.name] = c
		t._order.append(c.name)
	return t


static func _addon_of(node: SkillNode) -> RingCellAddon:
	for child in node.get_children():
		if child is RingCellAddon:
			return child
	return null


func centre() -> StringName:
	return _centre


## Every cell name, in authored order. The centre is not a cell.
func cells() -> Array[StringName]:
	return _order.duplicate()


func cell(name: StringName) -> Cell:
	return _cells.get(name, null)


func can_buy(spent: Array[StringName], name: StringName) -> bool:
	var c: Cell = _cells.get(name, null)
	if c == null or spent.has(name):
		return false
	for nb in c.neighbours:
		if nb == _centre or spent.has(nb):
			return true
	return false


func buyable(spent: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	for name in _order:
		if can_buy(spent, name):
			out.append(name)
	return out
