@tool
@abstract
class_name RangeFinder
extends Resource

## Encapsulates a reach model — "is [param candidate] within range of
## [param source]?" — Euclidean distance, graph hop count, owned-territory
## hops, line-of-sight, etc. Targeting subclasses compose a RangeFinder so
## reach concepts stay reusable across spells, weapons, abilities.
##
## Mirror of the Targeting pattern: a small abstract predicate, polymorphic
## via Resource subclasses, composable into the larger flow.
##
## Visualization is opt-in: subclasses override [method get_visual] to return
## a [RangeVisual] describing rings + edges to paint; the [code]ring_scene[/code]
## and [code]edge_scene[/code] exports let designers swap scenes (and thus
## shaders / colors / behaviours) without touching code.

const DEFAULT_RING_SCENE: PackedScene = preload("res://attack/range_finder/visuals/range_ring.tscn")
const DEFAULT_EDGE_SCENE: PackedScene = preload("res://attack/range_finder/visuals/range_edge.tscn")

@export var ring_scene: PackedScene = DEFAULT_RING_SCENE
@export var edge_scene: PackedScene = DEFAULT_EDGE_SCENE

## [param attacker] is only consulted for [method spell_range_multiplier] (and,
## on [HopRangeFinder], for its navigator) — it is NOT required to be mid-attack.
## Pass null to get the finder's raw exported reach with no stat scaling (e.g.
## a [CoreClass] aura, which should not scale with the caster's `spell_range`).
@abstract func in_range(attacker: Entity, source: SkillNode, candidate: SkillNode) -> bool


## Set-shaped sibling of [method in_range]: every node within reach of
## [param source], mapped to its distance, in [b]one traversal[/b] over
## [param mirror]. [param source] itself is included at distance 0.
##
## [b]This is not interchangeable with [method in_range].[/b] `in_range` on
## [HopRangeFinder] hardwires the [i]global[/i] navigator (reach through anyone's
## territory); `gather` traverses whatever mirror it is handed. That divergence is
## the point — an aura's hop distance must be measured over the [i]owned[/i]
## subgraph, or a path shortcuts through enemy land. Do not "simplify" `gather`
## to read `graph.navigator` for consistency; it silently breaks every owned-scope
## aura.
##
## Callers with per-node reach questions must use this, never `in_range` in a
## loop: `HopRangeFinder.in_range` runs an AStar query per candidate, so an N-node
## sweep is N × AStar. See `.claude/rules/graph.md`.
##
## The returned distance is what feeds an aura's [DistanceScale] — a bool
## predicate cannot express Halo's shell or the Ninja's per-hop debuff.
##
## [param attacker] (#385): default `null` preserves every existing aura call's
## behaviour bit-for-bit (unscaled reach, exactly as before this param existed).
## Pass a non-null attacker only to fold in [method spell_range_multiplier] —
## [MagicAttackPlan]'s highlight cache is the one caller that does.
func gather(source: SkillNode, mirror: GraphMirror, attacker: Entity = null) -> Dictionary[SkillNode, float]:
	var out: Dictionary[SkillNode, float] = {}
	if source == null or mirror == null:
		return out
	for n in mirror.get_mirrored_nodes():
		if n == source or in_range(attacker, source, n):
			# -1.0, NOT 0.0: the contract above promises the DISTANCE, and a
			# base class with no metric of its own cannot supply one. Writing
			# 0.0 answered "every node is exactly at the source", which a
			# DistanceScale would read as full magnitude everywhere. Both
			# concrete finders override this and nothing instantiates the base,
			# so -1.0 is an unreachable "no metric here" marker. Note it is NOT
			# the same meaning as `max_reach()`'s -1.0, which says *unbounded*;
			# they only share the shape of an out-of-band value.
			out[n] = -1.0
	return out


## Multi-source sibling of [method gather]: source -> (node -> distance), for
## every source in [param sources]. What [SpellTargetUnion] asks for when it
## inverts targeting (#728) — the whole point being that candidates come from
## the reach model FIRST, so the target predicates run over a bounded set
## instead of the whole board once per source.
##
## The default is one [method gather] per source, which is already the right
## shape for [HopRangeFinder]: its `gather` is a BOUNDED BFS, touching only
## nodes within reach, so total cost is O(sum of reachable), not O(sources x V).
## [EuclideanRangeFinder] overrides it — its `gather` is a full linear scan
## whether or not anything is in reach, so N sources really would cost N sweeps.
##
## Sources are kept separate rather than merged because the caller needs to
## know WHICH source reaches a target (`spell_damage` is node-local, so the
## choice is not moot) — a merged traversal answers "nearest source", which is
## the wrong question.
func gather_multi(sources: Array[SkillNode], mirror: GraphMirror,
		attacker: Entity = null) -> Dictionary[SkillNode, Dictionary]:
	var out: Dictionary[SkillNode, Dictionary] = {}
	for source in sources:
		if source == null:
			continue
		out[source] = gather(source, mirror, attacker)
	return out


## The reach bound this finder imposes, in its own metric, or -1.0 when
## unbounded. Feeds normalized scales (Linear, Curve) so they know their domain.
func max_reach() -> float:
	return -1.0


## Returns a [RangeVisual] describing what reach from [param source] looks
## like for [param attacker] (see [method in_range] for the null contract).
## Default is empty — subclasses populate rings (Euclidean) or edges
## (hop-based) as appropriate.
func get_visual(_attacker: Entity, _source: SkillNode) -> RangeVisual:
	return RangeVisual.new()


## Reach visual for a whole [SpellTargetUnion] — what the pick-spell-first
## selection draws before any source is committed (#728). Default empty, same
## contract as [method get_visual].
##
## [b]Not a loop over [method get_visual].[/b] That was the naive shape and it
## is quadratic: [method HopRangeFinder.get_visual] walks the entire edge list
## per call, so N eligible casters would walk it N times on an 800-node board.
## Subclasses fold [method SpellTargetUnion.merged_reach] — the per-source sets
## the target union was ALREADY built from — into one pass instead. No third
## traversal of the graph.
func get_union_visual(_attacker: Entity, _union: SpellTargetUnion) -> RangeVisual:
	return RangeVisual.new()


## Per-source reach multiplier — delegated to [SpellRangeRules], which owns the
## rule. A reach model answers "is this within N of that"; deciding what N is
## for a given caster is a stat question, and used to live here only by accident.
## Subclasses scale their base reach by this value so INT-driven boosts
## propagate uniformly across hop and euclidean finders.
## [param board] is the preview fallback for a caller that has a caster but no
## cast-from node yet ([SpellTooltip]) — see [method SpellRangeRules.multiplier].
static func spell_range_multiplier(
	attacker: Entity, source: SkillNode, board: StatBoard = null
) -> float:
	return SpellRangeRules.multiplier(attacker, source, board)
