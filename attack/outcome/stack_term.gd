@tool
@abstract
class_name StackTerm
extends Resource

## An extra the stacks a status rider lands gain at land time, added to the
## folded `stacks_per_hit` before crit, `stack_scale`, rounding and Greed
## ([method StatusInstance.land_on]). Evaluated against the world the status
## lands in — a shadow mid-resolve, the live world on a real landing — and never
## again: a rebuilt [AttackRecord] hit is [member StatusInstance.power_resolved].
## Authored on [member ApplyStatusEffect.stack_terms]; read-only at land, so a
## term is shared between every rider that copies it.


## Stacks this term adds. [param read] is the read node's slice (the
## attacker side), [param host] the receiving node's, both from the landing
## world and never null. The fold clamps a negative answer to 0.
func extra(_read: NodeCombat, _host: NodeCombat) -> float:
	return 0.0


## The term's readout line, `""` for "no line". [param read_node] is the
## carrier, null off one (a tray card, a shop, an off-carrier tooltip).
func describe(_read_node: SkillNode = null) -> String:
	return ""
