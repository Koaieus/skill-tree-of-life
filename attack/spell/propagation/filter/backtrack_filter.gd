@tool
class_name BacktrackFilter
extends PropagationFilter

## Vetoes travel back into any node the payload came from — the
## [member CastSpell.came_from] set.
##
## Deliberately reads the SET and not [member CastSpell.predecessor]: a
## convergence merges fronts that arrived from several directions at once, and
## a merged payload has to refuse all of them, not just the one the reducer
## picked as canonical. See [CycloneReducer].
##
## [b]An empty set allows everything[/b], and that is load-bearing rather than a
## degenerate case: [CycloneStep] mints a cycle-closing child with an empty
## `came_from`, so "the veto resets when the cycle completes" needs no branch
## here at all. This filter is one membership test, forever.
##
## [b]It does NOT cover self-loops, despite an earlier claim here that it did
## "by construction" (#699).[/b] The reasoning was that a self-loop hop has
## `to == from == payload.current_node` — true — and that the current node is
## therefore in the veto — false. This set holds the PREDECESSOR. A front that
## walked A → B carries `came_from = [A]`, so B → B sails straight through and
## crits on the next wave, which is Reverberator's mechanic wearing Cyclone's
## name. [NoSelfLoopFilter] is the fix, composed alongside this one, and the
## separation is the lesson: an unrelated rule that happens to cover your case
## is a rule that can stop covering it silently.


func allows(
		_from_node: SkillNode,
		to_node: SkillNode,
		payload: CastSpell,
		_ctx: PropagationContext) -> bool:
	return not payload.came_from.has(to_node)


func get_description() -> String:
	return "Never travels back the way it came."
