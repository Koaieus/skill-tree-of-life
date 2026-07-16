@tool
class_name SelfLoopCritCondition
extends CritCondition

## Crits when the target node has at least one self-loop edge.


func evaluate(_state: CastSpell, target: SkillNode, _outcome: AttackOutcome) -> bool:
	if target == null:
		return false
	return target.self_loop_count > 0
