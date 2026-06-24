@tool
class_name DegreeRanker
extends NodeRanker

## Live graph degree of the candidate. Drives Silencing Bolt / Resonator
## targeting (max-degree fan).


func score(node: SkillNode, _payload: CastSpell, ctx: PropagationContext) -> float:
	if ctx.graph == null or node == null:
		return 0.0
	return float(ctx.graph.get_neighbours(node).size())


func get_description() -> String:
	return "degree"
