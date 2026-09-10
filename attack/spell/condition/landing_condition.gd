@tool
@abstract
class_name LandingCondition
extends Resource

## A predicate over ONE landing: "given the state that arrived and the node it
## arrived on, is this true?" Pure and read-only — it reads [CastSpell]
## propagation facts (predecessor, incident_count, closed_cycle) and the graph,
## and mutates nothing.
##
## It has two consumers, which is why it is named for the question and not for
## an answer (it was `CritCondition` until #851, when the second one arrived):
##
## - [b]Crits[/b] — authored as [member SpellDef.crit_conditions] and OR-ed per
##   landing by [method SpellResolver._stamp_crit_conditions]. That slot keeps
##   its name: the SLOT is the crit consumer, the predicate is not.
## - [b]Conditional on-hit effects[/b] — [member ScaleDamageEffect.when]. The
##   Trailblazer's junction slam is exactly this: a [JunctionCondition] gating
##   a damage scale, where it used to be an `if` inside [TrailBlazerSpread].
##
## Subclass for concrete predicates (self-loop, leaf, junction, …) or use as a
## virtual hook for truly bespoke logic.


@abstract func evaluate(state: CastSpell, target: SkillNode, outcome: AttackOutcome) -> bool


## Player-facing fragment naming the shape this fires on — "on a leaf", "at a
## junction". Composed into spell copy; draft wording until #764.
func get_description() -> String:
	return ""
