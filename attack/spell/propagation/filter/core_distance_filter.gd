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
## Target entity = the owner of the landing's own seed
## ([member CastSpell.seed_node]) when non-caster and non-null — per landing, so
## each seed of an aimed cast homes on its own owner's core. If the seed isn't
## owned by a non-caster entity, the filter degrades to
## allow-all — Homing on an unowned target has no semantic meaning, so
## skipping the filter is more useful than blocking everything.

enum Direction { TOWARD, AWAY }

@export var direction: Direction = Direction.TOWARD


func allows(to: SkillNode, lctx: LandingContext) -> bool:
	var ctx := lctx.cast
	var from := lctx.node
	if ctx.graph == null or from == null or to == null:
		return false
	var core := _resolve_target_core(ctx, lctx.payload)
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


## The landing's own seed; a hand-built context with no payload (a filter
## asked outside a resolve) falls back to the cast's named target.
func _resolve_target_core(ctx: PropagationContext, payload: CastSpell) -> SkillNode:
	var named: SkillNode = payload.seed_node if payload != null else ctx.seed_node
	if named == null or named.owned_by == null:
		return null
	var owner: Entity = named.owned_by
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
