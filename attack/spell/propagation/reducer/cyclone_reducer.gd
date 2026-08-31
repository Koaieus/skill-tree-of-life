@tool
class_name CycloneReducer
extends IncidentReducer

## [MaxDamageReducer]'s damage rule, plus the two merge decisions Cyclone's
## cycle bookkeeping forces. Owner's spec, verbatim: [i]"max damage reducer,
## but: it makes the 'cast from' an array, and the step/propagation needs to
## veto all of them for travel"[/i].
##
## Three things happen here that the stock merge cannot do, and each is a hole
## in the naive version:
##
## [b]1. The veto set is the UNION of every incident's `came_from`.[/b] Travel
## is physical — the fronts really did arrive from all those directions, and the
## merged storm has to refuse all of them. The stock
## [method IncidentReducer._merge_payload_defaults] keeps only
## `incidents[0].predecessor`, so a merged payload would happily backtrack into
## the shoulder some other front came down. This union is also what produces
## [b]even-cycle extinction[/b]: two counter-rotating fronts colliding head-on
## at the antipodal node of a square or hexagon veto both shoulders between them
## and the arm strands. On an ODD ring they pass on an edge instead, never merge,
## and both lap home. Cyclone is a parity detector, and this line is why.
##
## [b]2. The crit trail is the WINNER's, not the union.[/b] The stock merge
## unions `visited` as a baked-in default; for Cyclone that would crit on nodes
## the surviving lineage never walked — and only when it happened to converge
## with someone who did. Inconsistency wearing flavour's clothes. The crit is
## narrative ([i]this lineage walked a loop, watch it come home[/i]), so the
## strongest incident's lineage survives whole.
##
## [b]3. Reset DOMINATES the union.[/b] When one incident closed a cycle and
## another didn't, a plain union hands the merged storm the non-closer's veto —
## an unrelated front silently weakening someone else's reset. So `closed_cycle`
## ORs (the owner's [i]"these combine as just 1 crit"[/i]), and if it fires, the
## payload resets outright: empty veto, trail restarted at this node. Note this
## also bounds hole 2 — on a closing wave the union is discarded, so a
## cross-lineage crit can only ever come from a NON-closing convergence.


func reduce(incidents: Array[CastSpell], node: SkillNode, _ctx: PropagationContext) -> CastSpell:
	var winner := MaxDamageReducer.strongest(incidents)
	var merged := _merge_payload_defaults(incidents, node)
	merged.damage = winner.damage

	var closed := false
	for inc in incidents:
		if inc.closed_cycle:
			closed = true
			break
	merged.closed_cycle = closed

	if closed:
		# Reset dominates: the loop closed here, so the storm is free to go
		# anywhere next and starts a fresh trail from this node.
		merged.came_from = []
		merged.visited = [node]
		return merged

	# The strongest lineage survives whole — NOT the union the base helper built.
	merged.visited = winner.visited.duplicate()
	var union: Array[SkillNode] = []
	for inc in incidents:
		for n in inc.came_from:
			if not union.has(n):
				union.append(n)
	merged.came_from = union
	return merged


func get_description() -> String:
	return "Converging fronts take the strongest and refuse every way they came."
