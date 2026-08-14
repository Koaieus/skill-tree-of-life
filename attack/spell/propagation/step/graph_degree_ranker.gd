@tool
class_name GraphDegreeRanker
extends NodeRanker

## Live GRAPH degree of the candidate — whole-board connectivity, not
## territory-relative. Not wired into any shipped spell today (2026-08-15):
## Reverberator climbs territory degree via [DegreeFilter] instead (#417),
## and Resonator fans to every neighbour and crits on convergence (#352) —
## neither reads a ranker at all. Kept as a ready piece for a future spell
## that deliberately wants "most connected on the whole board" (e.g. a
## greedy-max-degree design). [DegreeRanker] is the entity-degree default
## everywhere else (see [code].claude/rules/degree.md[/code]).


func score(node: SkillNode, _payload: CastSpell, ctx: PropagationContext) -> float:
	if ctx.graph == null or node == null:
		return 0.0
	return float(node.get_graph_degree(ctx.graph))


func get_description() -> String:
	return "degree"
