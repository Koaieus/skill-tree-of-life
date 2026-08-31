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
## Free side effect worth knowing: a self-loop hop has
## `to_node == from_node == payload.current_node`, which is always in
## `came_from` on a non-closing payload — so a spell wearing this filter is
## self-loop-blind by construction. That is what keeps Cyclone off
## Reverberator's turf.


func allows(
		_from_node: SkillNode,
		to_node: SkillNode,
		payload: CastSpell,
		_ctx: PropagationContext) -> bool:
	return not payload.came_from.has(to_node)


func get_description() -> String:
	return "Never travels back the way it came."
