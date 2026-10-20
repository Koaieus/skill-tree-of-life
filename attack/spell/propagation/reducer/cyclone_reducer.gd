@tool
class_name CycloneReducer
extends IncidentReducer

## Cyclone's merge: damage SUMS, lineage does not (#703).
##
## [b]Summing is the entire payoff.[/b] [CycloneSpread] hands each front a share
## of its damage below 1, so a thread that never meets another thread decays
## and dies. The only way power comes back is convergence, and this is where
## convergence pays: 0.70 arriving alongside 0.70 leaves as 1.40, stronger than
## the front that seeded them. Circulation is self-reinforcing and an offshoot
## is not — with no cycle detection anywhere in the loop, because a walk that
## folds back onto itself is a walk that keeps meeting itself.
##
## [b]The crit trail is the WINNER's, not the union.[/b] Unioning `visited`
## would crit on nodes the surviving lineage never walked, and only when it
## happened to converge with someone who did — inconsistency wearing flavour's
## clothes. The crit is narrative ([i]this lineage walked a loop, watch it come
## home[/i]), so the strongest incident's lineage survives whole even though its
## damage does not.
##
## [b]Closing DOMINATES[/b] the trail too: if any incident closed a cycle, the
## merged payload takes the strongest CLOSER's trail — the truncated ring — so
## the storm keeps lapping the loop it found; the strongest incident overall may
## be a non-closer carrying an ordinary path, and the trail has to be a ring
## some single lineage actually walked. The rest of the front's re-stamp
## (closing OR, came_from, the strength-weighted heading) is
## [method CycloneFront.merge], fed each incident's damage as its weight.


func reduce(incidents: Array[CastSpell], _cast: PropagationContext) -> CastSpell:
	var total := 0.0
	for inc in incidents:
		total += inc.damage
		var front := inc.extra(CycloneFront.ID) as CycloneFront.State
		if front != null:
			front.weight = inc.damage
	var merged := _merge_payload_defaults(incidents)
	merged.damage = total
	merged.visited = _lineage(incidents).visited.duplicate()
	return merged


## The strongest closer, else the strongest incident; ties to the earlier one.
static func _lineage(incidents: Array[CastSpell]) -> CastSpell:
	var closer: CastSpell = null
	for inc in incidents:
		var front := inc.extra(CycloneFront.ID) as CycloneFront.State
		if front != null and front.closed_cycle and (closer == null or inc.damage > closer.damage):
			closer = inc
	return closer if closer != null else MaxDamageReducer.strongest(incidents)


func get_description() -> String:
	return "Converging fronts add their power together."
