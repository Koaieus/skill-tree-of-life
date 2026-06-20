@tool
class_name ModifierPool
extends Resource

## Tiered-pick pool: roll a budget per node, then repeatedly draw an entry
## whose [member ModifierPoolEntry.cost] fits the remaining budget, subtract,
## repeat until nothing's affordable or [member max_picks] is hit.

@export var entries: Array[ModifierPoolEntry] = []
## Hard cap on picks per roll, regardless of leftover budget. 0 = no cap.
@export var max_picks: int = 0


## Returns a fresh list of duplicated [StatModifier]s. Duplication keeps
## procgen-produced modifiers independent of pool definitions so later tweaks
## (rolled values, runtime mutation) don't leak back.
func roll(budget: int, rng: RandomNumberGenerator) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	if entries.is_empty():
		return out
	var remaining := budget
	while true:
		if max_picks > 0 and out.size() >= max_picks:
			break
		var entry := _weighted_pick_affordable(remaining, rng)
		if entry == null or entry.modifier == null:
			break
		out.append(entry.modifier.duplicate(true))
		remaining -= entry.cost
		if remaining <= 0:
			break
	return out


func _weighted_pick_affordable(budget: int, rng: RandomNumberGenerator) -> ModifierPoolEntry:
	var total := 0.0
	for e in entries:
		if e != null and e.cost <= budget and e.weight > 0.0:
			total += e.weight
	if total <= 0.0:
		return null
	var r := rng.randf() * total
	for e in entries:
		if e == null or e.cost > budget or e.weight <= 0.0:
			continue
		r -= e.weight
		if r <= 0.0:
			return e
	return null
