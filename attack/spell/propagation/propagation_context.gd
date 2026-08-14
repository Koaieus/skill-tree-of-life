class_name PropagationContext
extends RefCounted

## Per-cast shared state, threaded through every wave of a spell resolution.
## Branches read & mutate this freely; the resolver bumps
## [member global_visit_count] after each successful merger application and
## reads it back to enforce [member PropagationConfig.max_visits_per_node]
## unconditionally, regardless of the active filter.
##
## Distinct from [CastSpell] — that's the per-branch payload (damage,
## hops_left, etc.); this is the per-cast ledger.

## How many times the merger has resolved an incident at each node during
## this cast. Filters and reducers may read & mutate freely; the resolver
## bumps it once per resolved incident, after effects fire.
var global_visit_count: Dictionary = {}  ## SkillNode -> int
## The graph this cast walks. Held here so filters/steps/reducers don't need
## it threaded as a separate argument.
var graph: Graph = null
## Caster of the spell. Read by [OwnerFilter] and similar owner-relative
## predicates.
var caster: Entity = null
## The seed node the cast started from. Useful for predicates like "must
## reach within N hops of seed" or "always step toward the seed's owner's
## core."
var seed_node: SkillNode = null
## Optional RNG, threaded into every minted [CastSpell] so stochastic
## propagation reproduces under a known seed. Null = fresh RNG per call.
var rng: RandomNumberGenerator = null
## Wave index of the current expansion (0 = seed wave). Filters / steps may
## read it for wave-dependent behaviour (rare; provided for completeness).
var wave_index: int = 0
## Lazily-built crit RNG, derived from [member rng] when a seed is present
## so crits reproduce without consuming the propagation stream (#213).
## Null = fresh RNG per call (match the documented fallback for [member rng]).
var crit_rng: RandomNumberGenerator = null


func visit_count(node: SkillNode) -> int:
	return int(global_visit_count.get(node, 0))


func bump_visit(node: SkillNode) -> void:
	global_visit_count[node] = visit_count(node) + 1


func rng_for_crits() -> RandomNumberGenerator:
	if crit_rng != null:
		return crit_rng
	crit_rng = RandomNumberGenerator.new()
	if rng != null:
		crit_rng.seed = rng.seed ^ 0xC217
	else:
		crit_rng.randomize()
	return crit_rng
