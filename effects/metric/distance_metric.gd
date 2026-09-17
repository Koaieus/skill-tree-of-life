@tool
@abstract
class_name DistanceMetric
extends Resource

## How far a node is from an aura's source. Orthogonal to [RangeFinder], which
## answers a different question: [i]which[/i] nodes the aura touches.
##
## Several designed auras answer the two with different metrics. The Serpent's
## penalty applies to every node the core can reach (topological) but scales by
## euclidean distance (spatial). Collapsing that into one `EuclideanRangeFinder`
## would force `max_distance` past the map diagonal and make the reach bound a
## trap: too small a value silently lets distant nodes escape the penalty
## entirely — the exact opposite of intent.
##
## Batch by design: a hop metric is one BFS for the whole set, never one query
## per node.

## Distance from [param source] to each of [param nodes] over [param mirror].
## [param hop_cap] is the caller's knowledge of how far a selected node can
## be in hops (the reach's bound), `-1` when it has none; a metric that walks
## the graph bounds itself by it, a spatial one ignores it (#943).
@abstract func distances(source: SkillNode, nodes: Array[SkillNode], mirror: GraphMirror, hop_cap: int = -1) -> Dictionary[SkillNode, float]


## Bound of this metric over [param nodes], for scales that normalize (Linear,
## Curve). -1.0 when there's nothing to measure.
static func max_of(dists: Dictionary[SkillNode, float]) -> float:
	var out: float = -1.0
	for d in dists.values():
		out = max(out, d)
	return out
