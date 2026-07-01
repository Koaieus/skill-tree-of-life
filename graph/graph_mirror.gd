@tool
class_name GraphMirror
extends Node

## Maintains an AStarSkillTree mirroring some subset of a [Graph]'s structural
## state. Subclasses decide *what* to mirror by overriding [method _should_mirror];
## the base handles the bookkeeping (vertex ids, signal hookup, queries).
##
## Sync modes:
## - Auto: call [method wire_to] in `_ready`. Base subscribes to graph signals
##   and reflects node/edge changes per `_should_mirror`. Used by [Navigator]
##   (mirrors everything) and [EntityNavigator] (mirrors owned nodes).
## - Manual: skip [method wire_to]; owner calls [method mirror_add] /
##   [method mirror_remove] directly. Used by plan-driven mirrors like a
##   melee blade selection.
##
## Mirror ops are idempotent. Edge ops only fire when both endpoints are
## mirrored (so unmirrored neighbours don't poke the astar with -1 ids).

@export var graph: Graph

var astar: AStarSkillTree = AStarSkillTree.new()
var _node_ids: Dictionary[SkillNode, int] = {}
var _ids_node: Dictionary[int, SkillNode] = {}


## Vertex id for [param node] in the mirror, or -1 if not mirrored.
func vertex_id(node: SkillNode) -> int:
	return _node_ids.get(node, -1)


## The [SkillNode] for vertex [param id], or null. O(1) reverse of [method vertex_id].
func node_for_id(id: int) -> SkillNode:
	return _ids_node.get(id, null)


## Add [param node] to the mirror. Idempotent. Connects any edges in [member graph]
## whose other endpoint is already mirrored.
func mirror_add(node: SkillNode) -> void:
	if _node_ids.has(node):
		return
	var id := astar.get_available_point_id()
	_node_ids[node] = id
	_ids_node[id] = node
	astar.add_point(id, node.global_position)
	if graph == null:
		return
	for e in graph.get_edges():
		var other: SkillNode = null
		if e.from == node:
			other = e.to
		elif e.to == node:
			other = e.from
		else:
			continue
		var other_id := vertex_id(other)
		# Skip self-loops (other_id == id): AStar2D rejects same-id connects.
		if other_id >= 0 and other_id != id and not astar.are_points_connected(id, other_id):
			astar.connect_points(id, other_id)


## Remove [param node] from the mirror. Idempotent.
func mirror_remove(node: SkillNode) -> void:
	var id: int = _node_ids.get(node, -1)
	if id < 0:
		return
	astar.remove_point(id)
	_node_ids.erase(node)
	_ids_node.erase(id)


## Subscribe to [member graph]'s structural signals and seed the mirror with
## already-present nodes that pass [method _should_mirror]. Idempotent on
## re-call (signal connections are guarded).
func wire_to(g: Graph) -> void:
	if g == null:
		push_warning("GraphMirror.wire_to called with null graph")
		return
	if not g.node_added.is_connected(_on_node_added):
		g.node_added.connect(_on_node_added)
	if not g.node_removed.is_connected(_on_node_removed):
		g.node_removed.connect(_on_node_removed)
	if not g.edge_added.is_connected(_on_edge_added):
		g.edge_added.connect(_on_edge_added)
	if not g.edge_removed.is_connected(_on_edge_removed):
		g.edge_removed.connect(_on_edge_removed)
	for sn in g.get_skill_nodes():
		if _should_mirror(sn):
			mirror_add(sn)


## Subclass hook: return true if [param node] should enter the mirror when
## the graph reports it (added / bootstrap). Default mirrors everything.
## Manual-sync subclasses (plan-driven) can ignore this — they don't call
## [method wire_to].
func _should_mirror(_node: SkillNode) -> bool:
	return true


# ── Queries ────────────────────────────────────────────────────────────────

## Every node currently in the mirror, in dictionary-iteration order. Cheap;
## callers that need a stable order should sort. Used by per-entity sweeps
## like turn-start HP refill on owned nodes.
func get_mirrored_nodes() -> Array[SkillNode]:
	var result: Array[SkillNode] = []
	for n in _node_ids:
		result.append(n)
	return result


## Degree of [param node] in the mirror — number of edges to other mirrored
## nodes. Returns -1 if the node isn't in the mirror so callers can tell
## "unowned" apart from "owned but isolated (degree 0)".
func get_degree(node: SkillNode) -> int:
	var id := vertex_id(node)
	if id < 0:
		return -1
	return astar.get_point_connections(id).size() + 2 * node.self_loop_count


## All mirrored nodes whose degree in the mirror equals [param degree].
func get_nodes_by_degree(degree: int) -> Array[SkillNode]:
	var result: Array[SkillNode] = []
	for node in _node_ids:
		var id: int = _node_ids[node]
		if astar.get_point_connections(id).size() == degree:
			result.append(node)
	return result


## Leaves of the mirrored subgraph — degree-1 nodes.
func get_leaf_nodes() -> Array[SkillNode]:
	return get_nodes_by_degree(1)


## Flood-fill the connected component containing [param node]. Disabled
## vertices are skipped. Returns [] if [param node] isn't mirrored.
func connected_component(node: SkillNode) -> Array[SkillNode]:
	var start_id := vertex_id(node)
	if start_id < 0:
		return []
	return _nodes_from_ids(_flood_from(start_id))


## Every mirrored node reachable from [param source] within [param max_hops]
## edges, mapped to its hop distance. [param source] is included at depth 0.
## [param max_hops] < 0 means unbounded. {} if [param source] isn't mirrored.
##
## The one true hop-bounded BFS — callers that need "everything within N hops"
## (core-move reachability, hop-based spell/attack reach) go through here instead
## of re-rolling a frontier loop.
func nodes_within(source: SkillNode, max_hops: int) -> Dictionary[SkillNode, int]:
	var result: Dictionary[SkillNode, int] = {}
	var start_id := vertex_id(source)
	if start_id < 0 or astar.is_point_disabled(start_id):
		return result
	var depths: Dictionary[int, int] = {start_id: 0}
	var frontier: Array[int] = [start_id]
	while not frontier.is_empty():
		var next_frontier: Array[int] = []
		for cur in frontier:
			var d: int = depths[cur]
			if max_hops >= 0 and d >= max_hops:
				continue
			for nb in astar.get_point_connections(cur):
				if depths.has(nb) or astar.is_point_disabled(nb):
					continue
				depths[nb] = d + 1
				next_frontier.append(nb)
		frontier = next_frontier
	for id in depths:
		result[node_for_id(id)] = depths[id]
	return result


## Fewest-hops path of nodes from [param from_node] to [param to_node]
## (inclusive of both ends), or [] if either isn't mirrored or no path exists.
## Hop count is [code]path.size() - 1[/code]. Relies on the unit-cost +
## zero-heuristic [AStarSkillTree] so the path is genuinely fewest-hops.
func path_between(from_node: SkillNode, to_node: SkillNode) -> Array[SkillNode]:
	var from_id := vertex_id(from_node)
	var to_id := vertex_id(to_node)
	if from_id < 0 or to_id < 0:
		return []
	var path: Array[SkillNode] = []
	for id in astar.get_id_path(from_id, to_id):
		path.append(node_for_id(id))
	return path


## All mirrored nodes that would lose reachability to [param anchor] if
## every node in [param nodes] were removed simultaneously. The removed
## nodes themselves are NOT included in the result.
##
## Powers (1) voluntary-deallocation gating ([method would_disconnect_from]),
## (2) post-damage forced cascade, (3) AoE spell preview (multi-hit).
func nodes_islanded_by_removing_set(nodes: Array[SkillNode], anchor: SkillNode) -> Array[SkillNode]:
	if anchor == null:
		return []
	var anchor_id := vertex_id(anchor)
	if anchor_id < 0:
		return []
	var disabled_ids: Array[int] = []
	for n in nodes:
		if n == null:
			continue
		var id := vertex_id(n)
		if id < 0:
			continue
		if not astar.is_point_disabled(id):
			astar.set_point_disabled(id, true)
			disabled_ids.append(id)
	var reachable := _flood_from(anchor_id)
	for id in disabled_ids:
		astar.set_point_disabled(id, false)
	var disabled_set: Dictionary[int, bool] = {}
	for id in disabled_ids:
		disabled_set[id] = true
	var result: Array[SkillNode] = []
	for n in _node_ids:
		var id: int = _node_ids[n]
		if reachable.has(id):
			continue
		if disabled_set.has(id):
			continue
		result.append(n)
	return result


## Convenience: single-node form of [method nodes_islanded_by_removing_set].
func nodes_islanded_by_removing(node: SkillNode, anchor: SkillNode) -> Array[SkillNode]:
	var single: Array[SkillNode] = [node]
	return nodes_islanded_by_removing_set(single, anchor)


## True iff removing [param node] would island any other mirrored node from
## [param anchor]. [param node] itself isn't counted.
func would_disconnect_from(node: SkillNode, anchor: SkillNode) -> bool:
	return not nodes_islanded_by_removing(node, anchor).is_empty()


# ── Signal handlers (subscribed in `wire_to`) ──────────────────────────────

func _on_node_added(node: SkillNode) -> void:
	if _should_mirror(node):
		mirror_add(node)


func _on_node_removed(node: SkillNode) -> void:
	mirror_remove(node)


func _on_edge_added(edge: Edge) -> void:
	var a := vertex_id(edge.from)
	var b := vertex_id(edge.to)
	if a < 0 or b < 0 or a == b:
		# AStar2D rejects self-loop edges (Condition "p_id == p_with_id").
		# Self-loops are a propagation/render concern, not a routing one —
		# pathfinding has no use for self → self.
		# Instead, the Edge is added to the self-loop array of the SkillNode vertex
		return
	if not astar.are_points_connected(a, b):
		astar.connect_points(a, b)


func _on_edge_removed(edge: Edge) -> void:
	var a := vertex_id(edge.from)
	var b := vertex_id(edge.to)
	if a < 0 or b < 0 or a == b:
		return
	if astar.are_points_connected(a, b):
		astar.disconnect_points(a, b)


# ── Internals ──────────────────────────────────────────────────────────────

func _flood_from(start_id: int) -> Dictionary[int, bool]:
	var visited: Dictionary[int, bool] = {}
	if astar.is_point_disabled(start_id):
		return visited
	visited[start_id] = true
	var queue: Array[int] = [start_id]
	while not queue.is_empty():
		var cur: int = queue.pop_back()
		for nb in astar.get_point_connections(cur):
			if astar.is_point_disabled(nb):
				continue
			if not visited.has(nb):
				visited[nb] = true
				queue.append(nb)
	return visited


func _nodes_from_ids(ids: Dictionary[int, bool]) -> Array[SkillNode]:
	var result: Array[SkillNode] = []
	for n in _node_ids:
		if ids.has(_node_ids[n]):
			result.append(n)
	return result
