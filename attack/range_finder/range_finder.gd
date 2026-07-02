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


## Returns a [RangeVisual] describing what reach from [param source] looks
## like for [param attacker] (see [method in_range] for the null contract).
## Default is empty — subclasses populate rings (Euclidean) or edges
## (hop-based) as appropriate.
func get_visual(_attacker: Entity, _source: SkillNode) -> RangeVisual:
	return RangeVisual.new()


## Per-attacker reach multiplier sourced from the `spell_range` stat
## (interpreted as a percent bonus). Returns 1.0 if no attacker / stat board
## (including a null attacker — the deliberate "no scaling" path).
## Subclasses scale their base reach by this value so INT-driven boosts
## propagate uniformly across hop and euclidean finders.
static func spell_range_multiplier(attacker: Entity) -> float:
	if attacker == null or attacker.stat_board == null:
		return 1.0
	var s := attacker.stat_board.get_stat(&"spell_range")
	if s == null:
		return 1.0
	return 1.0 + float(s.value) / 100.0
