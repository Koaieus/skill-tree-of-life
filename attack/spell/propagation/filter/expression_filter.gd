@tool
class_name ExpressionFilter
extends PropagationFilter

## One-off escape hatch: author a boolean GDScript [Expression] inline on
## the spell .tres. Mirrors the [ExpressionFormula] pattern in the stats
## system — declarative for the 5% of spells that need a custom predicate
## without a whole subclass.
##
## Available identifiers in the expression, and what each is measured on
## (#356's amendment — a binding table because the naming is NOT the repo-wide
## default: an unsuffixed `degree` reads as the TERRITORY one everywhere else,
## `.claude/rules/degree.md`, which is how #397's authored Trailblazer clause
## ended up on the wrong read):
##   [b]from_degree, to_degree[/b]               — int, whole-GRAPH degree
##                                                 ([method SkillNode.get_graph_degree])
##   [b]from_entity_degree, to_entity_degree[/b] — int, degree inside each
##                                                 node's own TERRITORY (0 if
##                                                 unallocated,
##                                                 [method SkillNode.get_entity_degree])
##   to_owned_by_caster, to_unallocated    — bool
##   damage, hops_remaining, hop_index     — payload state
##   visit_count                           — lctx.visit_count(to)

@export_multiline var expression: String = "true"

var _expr: Expression = null
var _last_text: String = ""


func allows(to: SkillNode, lctx: LandingContext) -> bool:
	var from := lctx.node
	var payload := lctx.payload
	var ctx := lctx.cast
	if from == null or to == null or ctx.graph == null:
		return false
	if _expr == null or _last_text != expression:
		_expr = Expression.new()
		var err := _expr.parse(expression, [
			"from_degree", "to_degree",
			"from_entity_degree", "to_entity_degree",
			"to_owned_by_caster", "to_unallocated",
			"damage", "hops_remaining", "hop_index",
			"visit_count",
		])
		if err != OK:
			push_warning("ExpressionFilter parse error: %s" % _expr.get_error_text())
			_expr = null
			return false
		_last_text = expression
	var inputs: Array = [
		from.get_graph_degree(ctx.graph),
		to.get_graph_degree(ctx.graph),
		from.get_entity_degree(ctx.graph),
		to.get_entity_degree(ctx.graph),
		# Both ownership reads go through the cast's world (#536), so a node
		# this same cast killed reads as unallocated here — see
		# [member PropagationContext.world]. `to_owned_by_caster` is the MINE
		# bit rather than `to.owned_by == payload.caster`, which additionally
		# fixes a null caster reading every unallocated node as its own.
		lctx.ownership_bit_of(to) == SkillNode.Ownership.MINE,
		not lctx.is_allocated_in_world(to),
		payload.damage,
		payload.hops_remaining,
		payload.hop_index,
		lctx.visit_count(to),
	]
	var result: Variant = _expr.execute(inputs, null, false)
	if _expr.has_execute_failed():
		return false
	return bool(result)


func get_description() -> String:
	return "Custom: %s" % expression
