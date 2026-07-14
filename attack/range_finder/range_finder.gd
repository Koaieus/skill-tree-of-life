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
func gather(source: SkillNode, mirror: GraphMirror) -> Dictionary[SkillNode, float]:
	var out: Dictionary[SkillNode, float] = {}
	if source == null or mirror == null:
		return out
	for n in mirror.get_mirrored_nodes():
		if n == source or in_range(null, source, n):
			out[n] = 0.0
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


## Per-source reach multiplier sourced from the `spell_range` stat
## (interpreted as a percent bonus), read node-locally off [param source] —
## wielder baseline merged with node-local addons, e.g. a range-extender
## granting local spell_range (#171). Returns 1.0 if no attacker / source
## (including a null attacker — the deliberate "no scaling" path, e.g. a
## [CoreClass] aura that should not scale with the caster's `spell_range`).
## Subclasses scale their base reach by this value so INT-driven boosts
## propagate uniformly across hop and euclidean finders.
static func spell_range_multiplier(attacker: Entity, source: SkillNode) -> float:
	if attacker == null or source == null:
		return 1.0
	return 1.0 + float(source.get_local_value(&"spell_range")) / 100.0
