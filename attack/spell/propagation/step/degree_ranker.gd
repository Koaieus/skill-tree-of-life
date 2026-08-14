@tool
class_name DegreeRanker
extends NodeRanker

## Live ENTITY degree of the candidate — degree within the candidate's own
## owner's territory (the induced subgraph of their `owned_by`), matching
## [DegreeFilter] and the game-wide default (see
## [code].claude/rules/degree.md[/code]). This is the ranker to reach for
## unless "most connected on the whole board regardless of ownership" is
## deliberately the metric — that's [GraphDegreeRanker].


func score(node: SkillNode, _payload: CastSpell, ctx: PropagationContext) -> float:
	if ctx.graph == null or node == null:
		return 0.0
	return float(node.get_entity_degree(ctx.graph))


func get_description() -> String:
	return "degree"
