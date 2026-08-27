@tool
class_name HopMetric
extends DistanceMetric

## Shortest-path edge count from the source, measured over the given mirror.
## One unbounded BFS for the whole set — shared across every hop-metric aura
## asking about the same (mirror, source) on the same topology generation via
## [AuraDistanceCache], since a walk this method does is one an entity may have
## several auras asking for at once (the Serpent's pair, both off the core)
## (#626).
##
## Pass an [EntityNavigator] to measure through owned territory only — that is
## what makes a Serpent's coil worth building, and what stops a path from
## shortcutting through enemy land.

func distances(source: SkillNode, nodes: Array[SkillNode], mirror: GraphMirror) -> Dictionary[SkillNode, float]:
	var out: Dictionary[SkillNode, float] = {}
	if source == null or mirror == null:
		return out
	var depths: Dictionary = AuraDistanceCache.get_or_walk(mirror, source, _walk.bind(source, mirror))
	for n in nodes:
		if depths.has(n):
			out[n] = float(depths[n])
	return out


## A topology change (allocate/deallocate) can shift the shortest path to
## anything beyond the changed node — the whole reason this metric needs the
## shared walk-and-diff rather than a per-node membership update. See
## [method EuclideanMetric.dirties_on_membership_change] for the metric that
## can safely answer false.
func dirties_on_membership_change() -> bool:
	return true


## The actual BFS — [-1 = unbounded flood; `nodes_within` skips its depth cap
## when max_hops < 0], wrapped as a zero-arg [Callable] for
## [method AuraDistanceCache.get_or_walk] to invoke on a cache miss.
func _walk(source: SkillNode, mirror: GraphMirror) -> Dictionary[SkillNode, float]:
	var depths: Dictionary[SkillNode, int] = mirror.nodes_within(source, -1)
	var out: Dictionary[SkillNode, float] = {}
	for n in depths:
		out[n] = float(depths[n])
	return out
