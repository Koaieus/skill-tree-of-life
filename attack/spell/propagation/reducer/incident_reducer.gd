@tool
@abstract
class_name IncidentReducer
extends Resource

## Resolves ≥1 simultaneous incidents arriving at the same node in the same
## BFS wave into a single resolved [CastSpell] (or null to CANCEL).
##
## Returning null means: no effect lands at this node in this wave, AND no
## further propagation from this node in this wave. The resolver still
## emits a cancellation entry on the outcome so VFX can hook a fizzle.
##
## Stock reducers operate on damage; visited-union + hops_left=max are
## baked-in defaults via [method _merge_payload_defaults] — not author-facing
## knobs.


@abstract func reduce(
		incidents: Array[CastSpell],
		node: SkillNode,
		ctx: PropagationContext) -> CastSpell


func get_description() -> String:
	return ""


## Build a resolved payload that carries the merged metadata (max hops_left,
## union of visited, any-non-null caster/source/rng). Subclasses call this
## then set the resolved damage themselves.
static func _merge_payload_defaults(incidents: Array[CastSpell], node: SkillNode) -> CastSpell:
	var merged := CastSpell.new()
	merged.current_node = node
	merged.seed_node = incidents[0].seed_node
	# Immutable across the whole cast, like seed_node — a merged payload that
	# lost it would hand ScaledAddProgression a seed of 0 past a convergence.
	merged.seed_damage = incidents[0].seed_damage
	merged.source = incidents[0].source
	merged.caster = incidents[0].caster
	merged.graph = incidents[0].graph
	merged.rng = incidents[0].rng
	merged.hop_index = incidents[0].hop_index
	# Handedness is constant for a whole cast (Curl ranks in one fixed direction
	# at every node), so first-wins here is exact rather than a choice.
	#
	# `arrival_share` is deliberately NOT merged: it describes ONE arc's mint,
	# and once the fronts have summed there is no such thing as the merged
	# payload's share. The per-arc values are read straight off `incidents` by
	# SpellResolver, in the same pass that captures `predecessors`, so the two
	# arrays cannot drift out of alignment (#704).
	merged.turn_sign = incidents[0].turn_sign
	# Inbound predecessor: this merged payload keeps only the CHOSEN one — the
	# canonical "the projectile has to fly from somewhere" reader (VFX origin,
	# and anything downstream that wants "the" predecessor rather than the
	# full converging set). Picking first here does NOT lose the rest of the
	# set: SpellResolver captures every incident's predecessor straight off
	# `incidents` at the grouping pass, before this reducer ever runs, and
	# stamps the full array onto the emitted PropagationEvent's
	# `predecessors` (#542). This field only ever needed to pick one.
	merged.predecessor = incidents[0].predecessor
	# hops_remaining: take MAX — gives the merged incident the most generous
	# remaining budget across its inputs.
	var hops_max: int = incidents[0].hops_remaining
	# visited: union of all branch visited-trails (per-branch state still
	# carried for filters that want it, even though ctx.global_visit_count
	# is the canonical revisit gate).
	var union: Array[SkillNode] = []
	var seen: Dictionary = {}
	for inc in incidents:
		if inc.hops_remaining > hops_max:
			hops_max = inc.hops_remaining
		for v in inc.visited:
			if not seen.has(v):
				seen[v] = true
				union.append(v)
	merged.hops_remaining = hops_max
	merged.visited = union
	return merged
