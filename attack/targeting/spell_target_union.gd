class_name SpellTargetUnion
extends RefCounted

## "Which targets can this spell hit, from anywhere I own, and from where is
## each one best hit?" — the pick-spell-first inversion of targeting (#728).
##
## Before this, the player picked a cast-from node and only then saw what it
## could reach, and [AiController] enumerated (spell x owned-node x target)
## to find out the same thing. Both are the wrong way round: [b]source choice
## is nearly always degenerate[/b], so the interesting set is the UNION of
## every eligible caster's reach, with the source auto-picked per target.
##
## [b]It is not moot, though[/b], which is why [member best_source] exists at
## all: `spell_damage` is node-local (a [CoreAura] can grant more of it the
## closer to the core), so the same spell on the same target hits differently
## depending on which owned node casts it. This picks the strongest available
## caster per target, silently — measured spread (Ninja +40%, Serpent ~flat)
## sits under the bar the issue set for earning a player-facing affordance.
##
## [b]Vision is deliberately absent.[/b] The union answers reachability only;
## each caller applies its own viewer's fog ([VisionSystem.is_visible] for the
## player UI, [AiRecon] for the AI). Baking one viewer's fog in here would be
## actively wrong under [SeatPolicy] couch handover, where the acting entity is
## not the viewing seat.

## Owned nodes that clear the spell's [member SpellDef.min_degree] — the
## casters this union was built from. Empty means "no eligible source", a
## structurally different dead end from an empty [method targets] (nothing in
## reach): one is fixed by growing territory, the other by moving.
var sources: Array[SkillNode] = []

## Membership view onto [member sources], for the per-node question
## [method MagicAttackPlan.get_node_role] asks on every repaint — an
## [code]Array.has[/code] there would be 800 x |owned| scans a frame.
##
## NOT foldable into [member per_source]'s keys, close as they look:
## [method build_for] leaves the candidate map empty when the graph has no
## navigator, so `per_source` can be empty while `sources` is not — and that
## gap is exactly the "no eligible source" vs "no valid target" distinction
## the union exists to keep separate.
var _source_set: Dictionary[SkillNode, bool] = {}

## source -> (node -> distance in that finder's own metric), straight off
## [method RangeFinder.gather_multi]. [b]Everything in reach, targetable or
## not[/b] — this is the REACH, and it is what the range visual is drawn from:
## folding these into one merged depth map ([method merged_reach]) lights each
## edge once instead of once per source. Distances are kept for the same
## reason; a bool set cannot fade a frontier.
var per_source_reach: Dictionary[SkillNode, Dictionary] = {}

## source -> (node -> true) for the LEGAL targets only — [member per_source_reach]
## narrowed by the targeting's ownership filter. Separate from the reach on
## purpose: an empty target set inside a drawn reach is the ordinary "nothing
## hostile is in range" read, and collapsing the two would erase it.
var per_source: Dictionary[SkillNode, Dictionary] = {}

## target -> the auto-picked caster for it: highest node-local `spell_damage`,
## tiebroken by LOWEST stable id. The tiebreak is not cosmetic — an
## order-dependent pick would make a host and a client disagree about which
## source a target maps to, and the source ships in the launch command.
var best_source: Dictionary[SkillNode, SkillNode] = {}


## True iff at least one owned node can cast the spell at all. Distinct from
## [method has_targets] — see [member sources].
func has_eligible_sources() -> bool:
	return not sources.is_empty()


## Is [param node] one of the eligible casters this union was built from?
## What the caster highlight paints, and the membership sibling of
## [method can_target].
func is_source(node: SkillNode) -> bool:
	return node != null and _source_set.has(node)


func has_targets() -> bool:
	return not best_source.is_empty()


func targets() -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for t in best_source:
		out.append(t)
	return out


## Membership test for the painted target set.
func can_target(node: SkillNode) -> bool:
	return node != null and best_source.has(node)


## The caster this union would use for [param node], or null if it isn't a
## target. What [MagicAttackPlan] stamps as its source on a target click.
func source_for(node: SkillNode) -> SkillNode:
	return best_source.get(node)


## Legal targets reachable from [param source] alone, membership-only — the
## source-scoped VIEW onto this union. [MagicAttackPlan] serves its existing
## per-source valid-target cache out of here instead of walking the graph a
## second time, so there is exactly one implementation behind both.
##
## It COPIES, so a caller that only needs a membership test in a hot loop
## should read [member per_source] directly — [method
## AiController._gather_magic_candidates] does.
func targets_from(source: SkillNode) -> Dictionary[SkillNode, bool]:
	var out: Dictionary[SkillNode, bool] = {}
	var found: Dictionary = per_source.get(source, {})
	for n in found:
		out[n] = true
	return out


## Build the union of [param spell]'s reach across every owned node of
## [param attacker] that may cast it.
##
## [b]Loop order is the whole perf story.[/b] The obvious implementation calls
## [method Targeting.valid_targets] once per source, and that runs
## [code]_filter_skill_nodes[/code] — a sweep of ALL 800 nodes — per source.
## No cache level fixes the cost of the first call. So candidates come from the
## range finder FIRST ([method RangeFinder.gather_multi]: a bounded BFS per
## source for hops, one merged sweep for euclidean), and the non-range target
## predicate runs only over those.
##
## [param plan] is needed only by the non-[NodeTargeting] fallback, which has
## no candidate-first path to take; nothing ships such a targeting today.
static func build(spell: SpellDef, attacker: Entity, graph: Graph,
		plan: AttackPlan = null) -> SpellTargetUnion:
	if spell == null or attacker == null:
		return SpellTargetUnion.new()
	var sources: Array[SkillNode]
	if attacker.spellbook != null:
		sources = attacker.spellbook.eligible_sources(spell, attacker)
	else:
		sources = _eligible_sources_without_book(spell, attacker)
	return build_for(spell, attacker, graph, sources, plan)


## [method build] over an EXPLICIT source list, skipping the eligibility
## question. One production caller: [MagicAttackPlan._rebuild_target_cache],
## serving its source-scoped valid-target view for a stamped source the current
## union does not list — see there for what still produces one (a stamped
## caster that has since become ineligible). Pre-#745 the AI drove this
## constantly, probing one owned node at a time; it now consumes
## [member per_source] off a single whole-territory [method build] per spell.
## That leaves this entry point close to unused — there is a TODO at the call
## site weighing whether it should fold back into [method build].
## Building over one source costs exactly what the pre-#728 single-source
## gather did, and keeps both views behind one implementation instead of
## resurrecting the old walk.
static func build_for(spell: SpellDef, attacker: Entity, graph: Graph,
		sources: Array[SkillNode], plan: AttackPlan = null) -> SpellTargetUnion:
	var union := SpellTargetUnion.new()
	if spell == null or spell.targeting == null or attacker == null or graph == null:
		return union
	union.sources = sources
	for src in sources:
		if src != null:
			union._source_set[src] = true
	if union.sources.is_empty():
		return union

	var targeting := spell.targeting
	if not (targeting is NodeTargeting):
		# No reach model to invert against — fall back to the O(N) walk per
		# source. Nothing ships a non-NodeTargeting spell; this exists so the
		# union stays total rather than silently empty if one ever does.
		for source in union.sources:
			var found: Dictionary[SkillNode, bool] = {}
			var reach: Dictionary[SkillNode, float] = {}
			for sn in targeting.valid_targets(plan, source):
				found[sn] = true
				reach[sn] = 0.0
			union.per_source[source] = found
			union.per_source_reach[source] = reach
		union._pick_best_sources(graph)
		return union

	var nt := targeting as NodeTargeting
	var finder: RangeFinder = nt.range_finder
	var candidates: Dictionary[SkillNode, Dictionary] = {}
	if finder == null:
		# Unlimited reach: every graph node is a range candidate, from every
		# source. Distance is meaningless here (there is no metric), so 0.0 —
		# and there is no reach visual to fold it into either.
		for source in union.sources:
			var all: Dictionary[SkillNode, float] = {}
			for sn in graph.get_skill_nodes():
				all[sn] = 0.0
			candidates[source] = all
	elif graph.navigator != null:
		# Global reach — the full-graph Navigator mirror, matching
		# HopRangeFinder/EuclideanRangeFinder.in_range, neither of which is
		# scoped to owned territory. NOT attacker.navigator.
		candidates = finder.gather_multi(union.sources, graph.navigator, attacker)

	for source in candidates:
		var legal: Dictionary[SkillNode, bool] = {}
		var reach_map: Dictionary = candidates[source]
		for candidate: SkillNode in reach_map:
			if candidate.ownership_bit(attacker) & nt.ownership_filter != 0:
				legal[candidate] = true
		union.per_source[source] = legal
		union.per_source_reach[source] = reach_map
	union._pick_best_sources(graph)
	return union


## [SpellBook]-free eligibility, mirroring
## [method MagicAttackPlan._source_meets_min_degree]'s fallback: tests and
## scripted setups that never build a book still get a working gate.
static func _eligible_sources_without_book(spell: SpellDef, attacker: Entity) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	if attacker.navigator == null:
		return out
	for n in attacker.navigator.get_mirrored_nodes():
		if attacker.navigator.get_degree(n) >= spell.min_degree:
			out.append(n)
	return out


## Collapse [member per_source] into [member best_source]: strongest local
## `spell_damage` wins, lowest stable id breaks a tie. Reads the id through
## the graph rather than caching one on the node, so a node that isn't
## registered (a hand-built fixture) simply falls back to insertion order via
## a stable id of 0 — deterministic within a peer, which is all a test needs.
func _pick_best_sources(graph: Graph) -> void:
	for source in per_source:
		var power := float(source.get_local_value(&"spell_damage"))
		var id := graph.get_stable_id(source) if graph != null else 0
		for target: SkillNode in per_source[source]:
			var incumbent: SkillNode = best_source.get(target)
			if incumbent == null:
				best_source[target] = source
				continue
			var inc_power := float(incumbent.get_local_value(&"spell_damage"))
			if power > inc_power:
				best_source[target] = source
			elif power == inc_power:
				var inc_id := graph.get_stable_id(incumbent) if graph != null else 0
				if id < inc_id:
					best_source[target] = source


## Merged reach for the whole union, as [RangeFinder]'s own metric: node ->
## SMALLEST distance across every eligible source. One map, so the hop reach
## visual lights each edge once instead of once per source.
func merged_reach() -> Dictionary[SkillNode, float]:
	var out: Dictionary[SkillNode, float] = {}
	for source in per_source_reach:
		var reach: Dictionary = per_source_reach[source]
		for n: SkillNode in reach:
			var d := float(reach[n])
			if not out.has(n) or d < out[n]:
				out[n] = d
	return out
