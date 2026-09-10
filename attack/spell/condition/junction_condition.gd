@tool
class_name JunctionCondition
extends LandingCondition

## True when the landed node is a JUNCTION — three or more of its owner's own
## edges meet there ([b]entity[/b] degree > 2).
##
## Entity degree, never graph degree, and that is the spell's premise rather
## than an implementation detail: the Trailblazer is about the DEFENDER's
## constellation shape, so an unrelated enemy node brushing past the string
## must not read as a junction. This is the identical read
## [TrailBlazerStep] made inline until #851 — see `docs/domain/degree.md`.
##
## Drives both halves of the Trailblazer's ending: the [ScaleDamageEffect]
## slam that fires here, and (as the mirrored `from_entity_degree <= 2` clause
## on the spell's [ExpressionFilter]) the fact that the walk cannot leave.


func evaluate(state: CastSpell, target: SkillNode, _outcome: AttackOutcome) -> bool:
	if state == null or target == null or state.graph == null:
		return false
	return target.get_entity_degree(state.graph) > 2


func get_description() -> String:
	return "at a junction"
