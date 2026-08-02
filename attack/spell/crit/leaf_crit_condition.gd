@tool
class_name LeafCritCondition
extends CritCondition

## Crits when the target is a leaf of ITS OWNER'S territory — degree 1 within
## the owner's induced subgraph, matching [DegreeFilter]. A node whose only
## other neighbour belongs to someone else dangles off its owner's land and
## crits, even though its whole-graph degree is 2. See `docs/domain/degree.md`.
##
## The resolver supplies the graph via [member CastSpell.graph]; the entity is
## the node's own [member SkillNode.owned_by] (the accessor's default).


func evaluate(state: CastSpell, target: SkillNode, _outcome: AttackOutcome) -> bool:
	if target == null or state == null or state.graph == null:
		return false
	return target.get_entity_degree(state.graph) == 1
