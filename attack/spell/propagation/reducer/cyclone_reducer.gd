@tool
class_name CycloneReducer
extends IncidentReducer

## Cyclone's merge: damage SUMS, lineage does not (#703).
##
## [b]Summing is the entire payoff.[/b] [CycloneStep] hands each front a share
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
## [b]Closing DOMINATES.[/b] `closed_cycle` ORs across incidents, and if it
## fires the merged payload takes a CLOSER's lineage whole: the truncated ring
## as its trail, so the storm keeps lapping the loop it found. The closer is
## picked by damage among the closers rather than overall, because the trail has
## to be a ring some single lineage actually walked and the strongest incident
## may be a non-closer carrying an ordinary path.
##
## [b]`came_from` is no longer a veto set[/b], and the union that used to be
## built here is gone with it. Cyclone dropped [BacktrackFilter] at #703: the
## curl measures its ranking FROM the arrival edge and so never offers it, which
## is a stronger guarantee than a filter could give a merged front. The field is
## still stamped for other spells' filters and for telemetry.


func reduce(incidents: Array[CastSpell], node: SkillNode, _ctx: PropagationContext) -> CastSpell:
	var winner := MaxDamageReducer.strongest(incidents)
	var merged := _merge_payload_defaults(incidents, node)

	var total := 0.0
	var closer: CastSpell = null
	for inc in incidents:
		total += inc.damage
		if inc.closed_cycle and (closer == null or inc.damage > closer.damage):
			closer = inc
	merged.damage = total
	merged.closed_cycle = closer != null

	var lineage: CastSpell = closer if closer != null else winner
	merged.visited = lineage.visited.duplicate()
	# Typed, not a bare `[]`: `came_from` is an Array[SkillNode] and an untyped
	# literal fails the assignment at runtime, inside the reducer, where it
	# silently takes every merge down with it.
	var cleared: Array[SkillNode] = []
	merged.came_from = cleared if closer != null else lineage.came_from.duplicate()
	return merged


func get_description() -> String:
	return "Converging fronts add their power together."
