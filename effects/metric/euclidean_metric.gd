@tool
class_name EuclideanMetric
extends DistanceMetric

## Straight-line scene-pixel distance from the source. Ignores topology entirely
## — two nodes may be adjacent in space and many hops apart, which is exactly the
## tension the Serpent is built on.

func distances(source: SkillNode, nodes: Array[SkillNode], _mirror: GraphMirror) -> Dictionary[SkillNode, float]:
	var out: Dictionary[SkillNode, float] = {}
	if source == null:
		return out
	for n in nodes:
		out[n] = source.global_position.distance_to(n.global_position)
	return out
