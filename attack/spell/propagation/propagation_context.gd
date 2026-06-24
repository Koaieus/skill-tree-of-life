class_name PropagationContext
extends RefCounted

## Per-cast shared state, threaded through every wave of a spell resolution.
## Branches read & mutate this freely; the resolver bumps
## [member global_visit_count] after each successful merger application, and
## [MaxVisitsFilter] reads it to gate revisits.
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


func visit_count(node: SkillNode) -> int:
	return int(global_visit_count.get(node, 0))


func bump_visit(node: SkillNode) -> void:
	global_visit_count[node] = visit_count(node) + 1
