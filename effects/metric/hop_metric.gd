@tool
class_name HopMetric
extends DistanceMetric

## Shortest-path edge count from the source, measured over the given mirror.
## One unbounded BFS for the whole set.
##
## Pass an [EntityNavigator] to measure through owned territory only — that is
## what makes a Serpent's coil worth building, and what stops a path from
## shortcutting through enemy land.

func distances(source: SkillNode, nodes: Array[SkillNode], mirror: GraphMirror) -> Dictionary[SkillNode, float]:
	var out: Dictionary[SkillNode, float] = {}
	if source == null or mirror == null:
		return out
	# -1 = unbounded flood; `nodes_within` skips its depth cap when max_hops < 0.
	var depths: Dictionary[SkillNode, int] = mirror.nodes_within(source, -1)
	for n in nodes:
		if depths.has(n):
			out[n] = float(depths[n])
	return out
