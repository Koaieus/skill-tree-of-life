class_name RingSilhouette
extends RefCounted
## The build an entity wears on its hero card: a pure builder from a
## [RingTable] plus that entity's `ring_spent` to a read-only [AspectWheel]'s
## entries, and the sector its rim takes. No state, no nodes.
##
## One entry per aspect, in the order the aspect first appears in
## [method RingTable.cells] (ring order, so an aspect keeps its angle). An
## entry's value is the sum of its bought cells' tiers, so T1 + T2 reads
## fuller than T1 alone. Entries are left pickable: the card's wheel is
## `read_only`, which keeps the aspect hue a `disabled_reason` would grey out.

## Tie-break order for [method dominant_sector], by [member Identity.id].
const SECTOR_ORDER: Array[StringName] = [
	&"strength", &"dexterity", &"intelligence", &"constitution", &"perception", &"wisdom",
]


static func entries(table: RingTable, spent: Array[StringName]) -> Array[AspectWheelEntry]:
	var out: Array[AspectWheelEntry] = []
	if table == null:
		return out
	var by_id: Dictionary[StringName, AspectWheelEntry] = {}
	for name in table.cells():
		var c := table.cell(name)
		var aspect := c.aspect as Aspect
		if aspect == null or aspect.identity == null:
			continue  # a keystone: it counts toward its sector, not a wedge
		var id := aspect.id()
		var entry: AspectWheelEntry = by_id.get(id, null)
		if entry == null:
			entry = AspectWheelEntry.new(id, aspect.identity, 0)
			entry.hub_text = aspect.identity.noun
			by_id[id] = entry
			out.append(entry)
		if spent.has(name):
			entry.value += maxi(1, c.tier)
	return out


## The sector holding the most bought cells (keystones included), ties broken
## by [constant SECTOR_ORDER]; null when nothing is bought.
static func dominant_sector(table: RingTable, spent: Array[StringName]) -> Identity:
	if table == null:
		return null
	var counts: Dictionary[StringName, int] = {}
	var sectors: Dictionary[StringName, Identity] = {}
	for name in spent:
		var c := table.cell(name)
		if c == null or c.sector == null:
			continue
		counts[c.sector.id] = counts.get(c.sector.id, 0) + 1
		sectors[c.sector.id] = c.sector
	var best: Identity = null
	var best_count := 0
	var best_rank := 0
	for id in counts:
		var rank := SECTOR_ORDER.find(id)
		if rank < 0:
			rank = SECTOR_ORDER.size()
		if counts[id] > best_count or (counts[id] == best_count and rank < best_rank):
			best = sectors[id]
			best_count = counts[id]
			best_rank = rank
	return best
