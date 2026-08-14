@tool
class_name GraphDegreeRanker
extends NodeRanker

## Live GRAPH degree of the candidate — whole-board connectivity, not
## territory-relative. Drives Silencing Bolt / Resonator targeting
## (max-degree fan). [DegreeRanker] is the entity-degree default everywhere
## else (see [code].claude/rules/degree.md[/code]); reach for this class only
## when "most connected on the board" is deliberately the metric.


func score(node: SkillNode, _payload: CastSpell, ctx: PropagationContext) -> float:
	if ctx.graph == null or node == null:
		return 0.0
	# Graph degree deliberately: Silencing Bolt / Resonator fan at whoever is
	# most connected on the board, not most connected within one territory.
	return float(node.get_graph_degree(ctx.graph))


func get_description() -> String:
	return "degree"
