@tool
class_name MaxDamageReducer
extends IncidentReducer

## Resolves to the strongest incident at this node — the sanity floor for
## spells that fan widely but shouldn't compound when they overlap.


func reduce(incidents: Array[CastSpell], node: SkillNode, _ctx: PropagationContext) -> CastSpell:
	var merged := _merge_payload_defaults(incidents, node)
	merged.damage = strongest(incidents).damage
	return merged


## The incident with the highest damage — the WINNER, not just the winning
## float. Ties go to the earliest in wave order, which keeps the pick stable
## under a replay (the resolver groups in incident order).
##
## Static and public because [CycloneReducer] needs the same winner to inherit
## its trail from, and two loops that must agree on "strongest" are exactly the
## parallel mirror that drifts.
static func strongest(incidents: Array[CastSpell]) -> CastSpell:
	var best: CastSpell = incidents[0]
	for inc in incidents:
		if inc.damage > best.damage:
			best = inc
	return best


func get_description() -> String:
	return "Converging incidents take the strongest."
