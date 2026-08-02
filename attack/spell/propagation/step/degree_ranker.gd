@tool
class_name DegreeRanker
extends NodeRanker

## Live graph degree of the candidate. Drives Silencing Bolt / Resonator
## targeting (max-degree fan).


func score(node: SkillNode, _payload: CastSpell, ctx: PropagationContext) -> float:
	if ctx.graph == null or node == null:
		return 0.0
	# Graph degree deliberately: Silencing Bolt / Resonator fan at whoever is
	# most connected on the board, not most connected within one territory.
	return float(node.get_graph_degree(ctx.graph))


func get_description() -> String:
	return "degree"
