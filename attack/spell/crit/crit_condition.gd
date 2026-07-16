@tool
@abstract
class_name CritCondition
extends Resource

## A spell-specific predicate that elevates a hit to a critical strike.
## Multiple conditions per spell run as OR — if ANY returns true the hit
## crits (in addition to the stat-based `crit_chance` roll). Follows the
## same composed-resource pattern as [OnHitEffect]: authored as an array
## on [SpellDef.crit_conditions], evaluated per landing in [SpellResolver].
##
## Subclass for concrete predicates (self-loop, leaf, degree-based, …)
## or use as a virtual hook for truly bespoke logic.


@abstract func evaluate(state: CastSpell, target: SkillNode, outcome: AttackOutcome) -> bool
