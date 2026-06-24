@tool
@abstract
class_name PropagationFilter
extends Resource

## Gate for "given current_node, may the spell copy itself to to_node?"
## Scoped to one virtual method by design — mirrors [RangeFinder]'s
## composability. Filter logic that doesn't fit a stock subclass goes in
## [ExpressionFilter] or a one-off subclass.


@abstract func allows(
		from_node: SkillNode,
		to_node: SkillNode,
		payload: CastSpell,
		ctx: PropagationContext) -> bool


func get_description() -> String:
	return ""
