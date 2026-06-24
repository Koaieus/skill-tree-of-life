@tool
class_name AddonPolicy
extends Resource

## Procgen v3 addon roll config. Independent of stat-modifier budget; the
## number of addons per node is sampled from `slot_count_weights` and each
## slot picks from `pool` via weighted draw with profiles.
##
## Unicity: addons declaring `unique = true` on their root [SkillNodeAddon]
## scene cannot stack — once one mints on a node, the entry is filtered out
## of subsequent slot picks for that same node.
##
## The weight pipeline shares its [WeightProfile] vocabulary with the modifier
## pass. The addon-pass [WeightContext] carries the modifier-pass output as
## `already_rolled` so profiles can react to what's already on the node.

## Slot-count distribution per node. Keys = total addons (int), values =
## sampling weights. Default `[0:60, 1:25, 2:12, 3:3]` — mean ~0.55, mostly
## zero with a long tail. `0` means "no addons this node".
@export var slot_count_weights: Dictionary = {0: 60.0, 1: 25.0, 2: 12.0, 3: 3.0}

@export var pool: AddonPool
@export var weight_profiles: Array[Resource] = []


## Sample a slot count from `slot_count_weights`. Returns 0 when the
## distribution is empty.
func sample_slot_count(rng: RandomNumberGenerator) -> int:
	if slot_count_weights.is_empty():
		return 0
	var total := 0.0
	for v in slot_count_weights.values():
		total += maxf(0.0, float(v))
	if total <= 0.0:
		return 0
	var r := rng.randf() * total
	for key in slot_count_weights.keys():
		var w := maxf(0.0, float(slot_count_weights[key]))
		r -= w
		if r <= 0.0:
			return maxi(0, int(key))
	return maxi(0, int(slot_count_weights.keys().back()))
