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
## The world this cast is walking (#536) — [method SpellResolver.resolve_against]
## sets it, and it is where every ownership question below is answered.
##
## [b]This is what makes the gate see the cast's own kills.[/b] A hit's target
## stays the real [SkillNode] throughout ([CombatWorld] explains why), so a node
## the resolver killed on wave 0 still reads as allocated if you ask the node.
## Asking the WORLD asks the slice the resolver actually mutated.
##
## Defaults to [method CombatWorld.live], so a hand-built context — a filter
## unit test, say — asks about the real world. That is the same code path, not
## a second branch: on a live world the lookup returns the node's own slice and
## every answer below is identical to reading the node directly.
var world: CombatWorld = CombatWorld.live()


## [param node]'s ownership relation to [member caster] in [member world] —
## exactly one [enum SkillNode.Ownership] bit. The ONE place a propagation
## predicate asks that question, so a filter cannot accidentally read the real
## node and miss this cast's own casualties.
func ownership_bit_of(node: SkillNode) -> int:
	var slice := world.combat_for(node)
	return slice.ownership_bit(caster) if slice != null else SkillNode.Ownership.NEUTRAL


## True if [param node] is allocated to anyone in [member world]. Twin of
## [method ownership_bit_of] for the predicates that don't care whose it is.
func is_allocated_in_world(node: SkillNode) -> bool:
	var slice := world.combat_for(node)
	return slice != null and slice.is_allocated()


## [param node]'s value for [param stat_id] as read in [member world] — the
## third twin of [method ownership_bit_of] / [method is_allocated_in_world],
## and the ONE place a propagation predicate reads a stat off a candidate.
##
## [b]This is what makes a ranker see the cast's own damage (#702).[/b] Asking
## `node.get_local_value` reads the LIVE slice, so a node the resolver hit on
## wave 0 still reads its pre-cast HP when wave 1 ranks it — the same trap
## [method ownership_bit_of] exists for, and one that only bites now that
## `node_health__current` is rankable: a pool CAP does not move mid-cast, a
## current does, every wave.
##
## Accepts accessor tokens (`<stat_id>__<accessor>`), since
## [method NodeCombat.get_local_value] does. Falls back to the node's own read
## when the world has no slice for it — an unallocated candidate has no combat
## state, and its stats are the node's own.
func local_value_of(node: SkillNode, stat_id: StringName) -> Variant:
	if node == null:
		return null
	var slice := world.combat_for(node)
	return slice.get_local_value(stat_id) if slice != null else node.get_local_value(stat_id)


func visit_count(node: SkillNode) -> int:
	return int(global_visit_count.get(node, 0))


func bump_visit(node: SkillNode) -> void:
	global_visit_count[node] = visit_count(node) + 1


func rng_for_crits() -> RandomNumberGenerator:
	if crit_rng != null:
		return crit_rng
	if rng != null:
		# Same derivation every mode uses (#507) — melee and ranged arm their
		# stream straight off `AttackPlan.resolve_seed`, and a cast's `rng` IS
		# that seed, so the salt has to be the one constant or the same attack
		# would draw different crits depending on which mode asked.
		crit_rng = CritRoll.stream_for(rng.seed)
	else:
		crit_rng = RandomNumberGenerator.new()
		crit_rng.randomize()
	return crit_rng
