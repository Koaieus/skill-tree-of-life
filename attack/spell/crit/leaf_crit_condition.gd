@tool
class_name LeafCritCondition
extends CritCondition

## Crits when the target is a leaf node (degree 1 in the graph).
## The resolver reads degree via the spell's [code]state.graph[/code].


func evaluate(state: CastSpell, target: SkillNode, _outcome: AttackOutcome) -> bool:
	if target == null or state == null or state.graph == null:
		return false
	return state.graph.get_neighbours(target).size() == 1
