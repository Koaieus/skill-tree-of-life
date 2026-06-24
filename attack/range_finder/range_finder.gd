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

@abstract func in_range(plan: AttackPlan, source: SkillNode, candidate: SkillNode) -> bool


## Returns a [RangeVisual] describing what reach from [param source] looks
## like under the current [param plan]. Default is empty — subclasses
## populate rings (Euclidean) or edges (hop-based) as appropriate.
func get_visual(_plan: AttackPlan, _source: SkillNode) -> RangeVisual:
	return RangeVisual.new()
