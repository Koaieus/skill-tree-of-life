@tool
@abstract
class_name PropagationFilter
extends Resource

## Gate for "given current_node, which of these candidates may the spell copy
## itself to?" — asked once per landing, over the whole candidate set.
##
## Two methods, one of which you almost never override. [method allows] is the
## pairwise question and the 95% case; [method narrow] is the set-level one and
## defaults to looping [method allows]. A filter whose rule genuinely needs the
## whole set at once — "the ones tying for highest degree" — overrides
## [method narrow] instead, and that is the ONLY place set-level narrowing
## lives (it used to be a parallel `RankPass` chain inside [TakeTopNSpread];
## #850 deleted it). Filter logic that doesn't fit a stock subclass goes in
## [ExpressionFilter] or a one-off subclass.


## Pairwise: may the spell hop from [param from_node] to [param to_node]?
##
## A PAIRWISE filter overrides this and gets [method narrow] for free. A
## SET-LEVEL filter overrides [method narrow] and DERIVES this from it, by
## narrowing the one-element set — never by asserting [code]true[/code], so
## the two answers cannot drift apart.
@abstract func allows(
		from_node: SkillNode,
		to_node: SkillNode,
		payload: CastSpell,
		ctx: PropagationContext) -> bool


## Set-level: which of [param candidates] survive? Order is preserved, so the
## step's stable tie-break still sees scene order from
## [method Graph.get_neighbours].
##
## The default is exactly the pairwise loop, so overriding [method allows]
## alone is enough for a stock filter.
func narrow(
		from_node: SkillNode,
		candidates: Array[SkillNode],
		payload: CastSpell,
		ctx: PropagationContext) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for c in candidates:
		if allows(from_node, c, payload, ctx):
			out.append(c)
	return out


func get_description() -> String:
	return ""
