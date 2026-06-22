@tool
class_name ArchetypePolicy
extends Resource

## Per-archetype clustering + identity config (procgen v2). Replaces the
## clustering+identity half of [NodeTypeDef] when [GraphProcgenConfig.archetypes]
## is populated and [GraphProcgenConfig.use_archetype_policies] is true.
##
## - `target_ratio` controls the archetype's share of total nodes. Ratios are
##   normalised across all archetypes in the config so they don't need to sum
##   to 1; relative weights are what matter.
## - `cluster_size_weights` controls the size DISTRIBUTION of same-archetype
##   connected components. The cluster planner samples sizes from this
##   dictionary until total ≥ target node count for the archetype, then BFS-
##   grows clusters through the pruned graph.
## - `cluster_jitter` is a per-node reroll chance after assignment — softens
##   cluster borders. 0 = pure clusters; 1 = ignore clustering entirely.
##   Defaults to 0 — clusters stay clean, opt in if you want messy borders.
## - `primary_stat` is the StatBoard id this archetype maps to (e.g. red →
##   `&"strength"`). Consumed by the phased modifier draw to bias toward
##   stat-coherent rolls. Empty = archetype has no primary stat (e.g. a pure
##   utility or wildcard archetype).
##
## Example shape:
##   id = &"red"
##   color = Color.RED
##   primary_stat = &"strength"
##   target_ratio = 0.25
##   cluster_size_weights = {3: 1.0, 4: 1.0, 5: 0.6, 6: 0.2}
##   cluster_jitter = 0.0

@export var id: StringName = &""
@export var color: Color = Color.WHITE
## The stat this archetype's nodes are themed around. Used by the phased
## modifier draw to weight primary vs off-attribute rolls.
@export var primary_stat: StringName = &""
@export_range(0.0, 1.0) var target_ratio: float = 0.0
## Dictionary[int, float]. Keys are cluster sizes (node counts); values are
## sampling weights. Empty = single-node "clusters" only.
@export var cluster_size_weights: Dictionary = {}
@export_range(0.0, 1.0) var cluster_jitter: float = 0.0
## Hard exclusion list: any pool entry whose `tags` overlap with this set
## gets weight 0 for nodes of this archetype. Use to enforce specialization
## (e.g. gold drops STR/DEX/INT/CON/PER content and only keeps WIS/xp_growth).
## Tighter than the `weights` dial: ArchetypeWeightProfile can depress to
## 0.05× but never zero; forbid_tags is a brick wall.
@export var forbid_tags: Array[StringName] = []


## Returns a cluster size sampled from `cluster_size_weights`, weighted-pick.
## Falls back to 1 if the distribution is empty.
func sample_cluster_size(rng: RandomNumberGenerator) -> int:
	if cluster_size_weights.is_empty():
		return 1
	var total := 0.0
	for v in cluster_size_weights.values():
		total += maxf(0.0, float(v))
	if total <= 0.0:
		return 1
	var r := rng.randf() * total
	for key in cluster_size_weights.keys():
		var w := maxf(0.0, float(cluster_size_weights[key]))
		r -= w
		if r <= 0.0:
			return maxi(1, int(key))
	# Shouldn't happen except for floating-point edge cases.
	return maxi(1, int(cluster_size_weights.keys().back()))
