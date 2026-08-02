@tool
class_name DegreeFilter
extends PropagationFilter

## Compares the candidate's live degree against the current node's, measured
## in each node's OWN territory — the induced subgraph of its `owned_by`, not
## the whole graph. Drives Leafblower (less-or-equal), and any future
## ridge-walker / climber (greater-than) variants.
##
## Entity degree, not graph degree, for two reasons. It matches the cast gate
## ([code]SpellBook._node_meets_source_requirements[/code] and
## [MagicAttackPlan] both read [method GraphMirror.get_degree] on the
## attacker's mirror), and on a contested board a defender's dangling leaf is
## routinely adjacent to two enemy nodes — graph degree reads that as a hub and
## hides it from a downhill walk, which is exactly the target Leafblower exists
## to reach.
##
## Each endpoint is measured in its own owner's subgraph. In a 3-way fight
## [code]from[/code] and [code]to[/code] can therefore belong to different
## entities and be compared across two subgraphs; that's intended — "downhill"
## means downhill relative to the land each node actually sits in.
##
## Self-loops count +2 per loop on both sides (see
## [method SkillNode.get_entity_degree]) — a fortified node genuinely reads as
## higher-degree and turns the walk away.

## NOTE on [constant LESS]: strict-downhill cannot traverse a chain at all —
## every interior node of a path has degree 2, so the walk stalls one hop past
## the seed. Leafblower ships [constant LESS_OR_EQUAL] for exactly that reason.
## Reach for [constant LESS] only when "one hop off a hub, no further" is the
## intent. Plateau-looping is not a risk either way:
## [member PropagationConfig.max_visits_per_node] terminates the walk.
enum Compare {
	LESS,           ## candidate.degree < current.degree (hub-adjacent only)
	LESS_OR_EQUAL,  ## candidate.degree ≤ current.degree (Leafblower)
	GREATER,        ## candidate.degree > current.degree (climber)
	GREATER_OR_EQUAL,
}

@export var compare: Compare = Compare.LESS


func allows(from: SkillNode, to: SkillNode, _payload: CastSpell, ctx: PropagationContext) -> bool:
	if ctx.graph == null or from == null or to == null:
		return false
	var cur: int = from.get_entity_degree(ctx.graph)
	var nb: int = to.get_entity_degree(ctx.graph)
	match compare:
		Compare.LESS: return nb < cur
		Compare.LESS_OR_EQUAL: return nb <= cur
		Compare.GREATER: return nb > cur
		Compare.GREATER_OR_EQUAL: return nb >= cur
	return false


func get_description() -> String:
	match compare:
		Compare.LESS: return "Downhill degree-flow only."
		Compare.LESS_OR_EQUAL: return "Degree-plateau or downhill."
		Compare.GREATER: return "Uphill degree-flow only."
		Compare.GREATER_OR_EQUAL: return "Degree-plateau or uphill."
	return ""
