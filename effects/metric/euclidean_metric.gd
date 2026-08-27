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


## Nodes don't move (#626 — see docs/domain/multiplayer-sync-model.md-adjacent
## reasoning: position is write-once outside procgen). An allocation or
## deallocation cannot change any OTHER node's straight-line distance from
## [param source] — only whether that one node is a member at all, which
## [AuraEffect] can update on its own without asking this metric to recompute
## the whole set.
func dirties_on_membership_change() -> bool:
	return false
