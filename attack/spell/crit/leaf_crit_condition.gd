@tool
class_name LeafCritCondition
extends CritCondition

## Crits when the target is a leaf node (degree 1 in the graph).
## The resolver reads degree via the spell's [code]state.graph[/code].


func evaluate(state: CastSpell, target: SkillNode, _outcome: AttackOutcome) -> bool:
	if target == null or state == null or state.graph == null:
		return false
	# TODO(degree-semantics): `owned_by`, not `owner` — `owner` is Godot's scene
	# owner and would hand a GameRoot to an `entity: Entity` param. Left on
	# entity degree so the crit agrees with DegreeFilter; see the open question
	# about whether SkillNode should answer this without the two arguments.
	return target.get_entity_degree(state.graph, target.owned_by) == 1
