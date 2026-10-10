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
## `weight_profiles` shares the [WeightProfile] vocabulary with the modifier
## pass, but the addon pass builds no [WeightContext] and does not apply them
## today; nothing from the modifier pass reaches an addon pick.

## Slot-count distribution per node. Keys = total addons (int), values =
## sampling weights. Default `[0:60, 1:25, 2:12, 3:3]` — mean ~0.55, mostly
## zero with a long tail. `0` means "no addons this node".
@export var slot_count_weights: Dictionary = {0: 60.0, 1: 25.0, 2: 12.0, 3: 3.0}

## Addon density: how many addons the post-loop pass places per 100 generated
## nodes, so maps of every size scale alike. Each one draws a node uniformly
## WITH replacement; a node drawn again gains one stake level. Tentative.
@export_range(0, 200, 0.5) var addons_per_100_nodes: float = 30.0

## Procgen's own per-node addon limit — a draw landing on a full node is
## redrawn. Not the player's stake ceiling: a rare 4th draw stakes the node to
## 4. Tentative.
@export_range(1, 8) var max_addons_per_node: int = 4

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
