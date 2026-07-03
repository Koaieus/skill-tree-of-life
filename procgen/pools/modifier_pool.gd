@tool
class_name ModifierPool
extends Resource

## Tiered-pick pool: roll a budget per node, then repeatedly draw an entry
## whose [member ModifierPoolEntry.cost] fits the remaining budget, subtract,
## repeat until nothing's affordable.
##
## Each draw calls [method ModifierPoolEntry.roll] to mint a fresh
## [StatModifier] with a value sampled from the entry's `value_range`.
## Per docs/domain/procgen-v2.md, the cost floor (≥1) is the implicit cap on
## per-node modifier count — no `max_picks` knob.

@export var entries: Array[ModifierPoolEntry] = []


func roll(budget: int, rng: RandomNumberGenerator) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	if entries.is_empty():
		return out
	var remaining := budget
	while remaining > 0:
		var entry := _weighted_pick_affordable(remaining, rng)
		if entry == null:
			break
		out.append(entry.roll(rng))
		remaining -= entry.cost
	return out


func _weighted_pick_affordable(budget: int, rng: RandomNumberGenerator) -> ModifierPoolEntry:
	var total := 0.0
	var partaking_entries := entries.filter(func(e: ModifierPoolEntry): return e.is_in_budget(budget) and e.has_weight())
	total = partaking_entries.reduce(func(tot: float, e: ModifierPoolEntry): return tot + e.weight, 0.)
	if total <= 0.0:
		return null
	var r := rng.randf() * total
	for e: ModifierPoolEntry in partaking_entries:
		r -= e.weight
		if r <= 0.0:
			return e
	return null
