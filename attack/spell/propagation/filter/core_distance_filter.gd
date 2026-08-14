@tool
class_name CoreDistanceFilter
extends PropagationFilter

## Allows only candidates that move CLOSER (or FARTHER) from the target's
## owner-Core. Drives Homing Decoring and Corifugal Bolt.
##
## UNSHIPPED: no spell preset composes this filter yet — no production or
## test `.tres` references [CoreDistanceFilter]. Kept for the two named
## spells it's designed for; delete if they don't materialize.
##
## Target entity = seed_node's owner (when non-caster and non-null). If
## the seed isn't owned by a non-caster entity, the filter degrades to
## allow-all — Homing on an unowned target has no semantic meaning, so
## skipping the filter is more useful than blocking everything.

enum Direction { TOWARD, AWAY }

@export var direction: Direction = Direction.TOWARD


func allows(from: SkillNode, to: SkillNode, _payload: CastSpell, ctx: PropagationContext) -> bool:
	if ctx.graph == null or from == null or to == null:
		return false
	var core := _resolve_target_core(ctx)
	if core == null:
		return true
	var d_from := _bfs_distance(ctx.graph, from, core)
	var d_to := _bfs_distance(ctx.graph, to, core)
	if d_from < 0 or d_to < 0:
		return false
	match direction:
		Direction.TOWARD: return d_to < d_from
		Direction.AWAY: return d_to > d_from
	return false


func get_description() -> String:
	match direction:
		Direction.TOWARD: return "Steps toward enemy core."
		Direction.AWAY: return "Steps away from enemy core."
	return ""


func _resolve_target_core(ctx: PropagationContext) -> SkillNode:
	if ctx.seed_node == null or ctx.seed_node.owned_by == null:
		return null
	var owner: Entity = ctx.seed_node.owned_by
	if owner == ctx.caster:
		return null
	return owner.core_location


## Lightweight BFS — graphs in this game are small enough that a per-call
## walk is fine. If perf shows up here, hoist into a cached distance map on
## the context at resolve start.
static func _bfs_distance(graph: Graph, from: SkillNode, to: SkillNode) -> int:
	if from == to:
		return 0
	var queue: Array = [from]
	var dist: Dictionary = {from: 0}
	while not queue.is_empty():
		var cur: SkillNode = queue.pop_front()
		var d: int = dist[cur]
		for nb in graph.get_neighbours(cur):
			if dist.has(nb):
				continue
			dist[nb] = d + 1
			if nb == to:
				return d + 1
			queue.append(nb)
	return -1
