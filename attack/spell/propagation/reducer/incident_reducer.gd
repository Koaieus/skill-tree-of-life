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
##
## The stack fold: [member stack_fold] folds the incidents'
## [member CastSpell.stack_weight]s into the landing's starting
## [member HitLanding.stack_scale] via [method fold_stacks] — a per-LANDING
## fact, never carried (the merged payload carries the MAX weight).

## How converging arrivals' status stacks fold into the one landing. MAX
## (default, attacker-favoured) lands the strongest arrival's stacks; SUM adds
## one share per converging branch; MIN the weakest present; FIRST the first.
enum StackFold { MAX, SUM, MIN, FIRST }

## See [enum StackFold]. Named by [method fold_description] when not MAX.
@export var stack_fold: StackFold = StackFold.MAX

## When on, every incident at a node lands its OWN arrival — on-hit effects and
## crit evaluation with that incident as the payload, in predecessor
## [method Graph.get_stable_id] order — while the visit bump and the departure
## still run once off [method reduce]'s merge. Off: one merged arrival.
@export var hit_each_incident: bool = false


## [b]Deliberately NOT a [LandingContext][/b] (#356): the reducer MAKES the
## landing, so none exists yet when it runs. Pre-landing stages take the cast
## ledger; at-landing stages take the landing. [param cast]'s [code]_ctx[/code]
## underscore in every stock reducer stays available for one that wants
## [method PropagationContext.visit_count] or [member PropagationContext.world] —
## it is no longer positionally dead-by-design, just unused by anything shipped.
@abstract func reduce(incidents: Array[CastSpell], cast: PropagationContext) -> CastSpell


func get_description() -> String:
	return fold_description()


## This reducer's [member stack_fold] over [param incidents]' stack weights.
func fold_stacks(incidents: Array[CastSpell]) -> float:
	return fold_of(incidents, stack_fold)


## [param fold] over [param incidents]' [member CastSpell.stack_weight]s —
## static so the resolver's null-reducer path folds MAX without an instance.
static func fold_of(incidents: Array[CastSpell], fold: StackFold) -> float:
	if incidents.is_empty():
		return 1.0
	var out: float = incidents[0].stack_weight
	if fold == StackFold.FIRST:
		return out
	for i in range(1, incidents.size()):
		var w: float = incidents[i].stack_weight
		match fold:
			StackFold.SUM:
				out += w
			StackFold.MIN:
				out = minf(out, w)
			_:
				out = maxf(out, w)
	return out


## The player-facing line for a non-default [member stack_fold]; "" at MAX.
## Stock reducers override [method get_description], so composers
## ([method PropagationConfig.get_description]) append this themselves.
func fold_description() -> String:
	match stack_fold:
		StackFold.SUM:
			return "Stacks add where branches meet."
		StackFold.MIN:
			return "Stacks take the weakest where branches meet."
		StackFold.FIRST:
			return "Stacks take the first arrival where branches meet."
	return ""


## Build a resolved payload carrying the merged metadata: [method CastSpell.derived]
## of the first incident, then MAX hops_remaining, the union of visited, MAX
## stack_weight and each extension's [method PayloadExtension.merge].
## Subclasses call this then set the resolved damage themselves.
static func _merge_payload_defaults(incidents: Array[CastSpell]) -> CastSpell:
	# Everything universal — seed, source, caster, graph, rng, seed_damage,
	# hop_index — is the first incident's (CastSpell.derived); a convergence
	# groups by node, so current_node is shared.
	#
	# Inbound predecessor: this merged payload keeps only the FIRST one — the
	# canonical "the projectile has to fly from somewhere" reader. The full
	# converging set is captured by SpellResolver off `incidents` before this
	# reducer runs and stamped onto the emitted PropagationEvent.
	var merged := CastSpell.derived(incidents[0])
	# hops_remaining: take MAX — gives the merged incident the most generous
	# remaining budget across its inputs.
	var hops_max: float = incidents[0].hops_remaining
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
	# The carried stack weight is MAX of the incidents — never the fold, which
	# is a per-landing fact: a SUM spell lands one share per converging branch
	# without compounding down the walk.
	merged.stack_weight = fold_of(incidents, StackFold.MAX)
	merged.visited = union
	# extras: each extension merges its own state across the incidents, through
	# the template the state points back at — every incident of one cast carries
	# them in [member PropagationConfig.extensions] order.
	for i in incidents[0].extras.size():
		var states: Array[PayloadState] = []
		for inc in incidents:
			states.append(inc.extras[i])
		merged.extras.append(incidents[0].extras[i].template.merge(states))
	return merged
