@tool
class_name DegreeFilter
extends PropagationFilter

## Compares the candidate's live graph degree against the current node's
## degree. Drives Leafblower (strict-less), and any future ridge-walker
## (less-or-equal) / climber (greater-than) variants.

enum Compare {
	LESS,           ## candidate.degree < current.degree (Leafblower default)
	LESS_OR_EQUAL,  ## candidate.degree ≤ current.degree (ridge-walker)
	GREATER,        ## candidate.degree > current.degree (climber)
	GREATER_OR_EQUAL,
}

@export var compare: Compare = Compare.LESS


func allows(from: SkillNode, to: SkillNode, _payload: CastSpell, ctx: PropagationContext) -> bool:
	if ctx.graph == null or from == null or to == null:
		return false
	var cur: int = ctx.graph.get_neighbours(from).size()
	var nb: int = ctx.graph.get_neighbours(to).size()
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
