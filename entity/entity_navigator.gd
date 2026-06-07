@tool
class_name EntityNavigator
extends Node

## Per-entity owned-subgraph AStar view. Mirrors only the SkillNodes owned by
## `entity` and the edges between them — i.e. the entity's induced subgraph.
##
## Drives connectivity questions like "would deallocating this node island
## any of my other owned nodes from my core?" (`is_cut_disconnecting_core`).
## Later combat code reads from `astar` directly for path / reach queries on
## the owned territory.
##
## Mutation contract: ownership writes happen through AllocationSystem,
## which calls `mirror_add` / `mirror_remove` on us. We don't subscribe to
## per-node `owner_changed` — programmatic `node.owned_by = X` outside the
## system would drift the mirror. Structural edge changes still come via
## graph signals so procgen / runtime topology edits stay in sync.

@export var entity: Entity
@export var graph: Graph

var astar: AStarSkillTree = AStarSkillTree.new()
var _node_ids: Dictionary[SkillNode, int] = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if entity == null:
		push_warning("EntityNavigator has no Entity reference")
		return
	if graph == null:
		push_warning("EntityNavigator has no Graph reference")
		return
	graph.edge_added.connect(_on_edge_added)
	graph.edge_removed.connect(_on_edge_removed)
	graph.node_removed.connect(_on_node_removed)
	# Bootstrap: pick up nodes already owned by us (Core wired by NodePath in
	# the scene, or a runtime-added entity that "inherits" some territory).
	for sn in graph.get_skill_nodes():
		if sn.owned_by == entity:
			mirror_add(sn)


## Vertex id in the owned-subgraph AStar, or -1 if `node` isn't ours.
func vertex_id(node: SkillNode) -> int:
	return _node_ids.get(node, -1)


## True iff deallocating `node` would leave another owned node unable to
## reach the entity's core. False for the core itself (deallocating it is
## a separate concern — core relocation or entity teardown), for orphan
## owned nodes (no neighbors to island), and when no core is set.
func is_cut_disconnecting_core(node: SkillNode) -> bool:
	if node == null or entity == null:
		return false
	if node.owned_by != entity:
		return false
	var core := entity.core_location
	if core == null or core == node:
		return false
	var core_id := vertex_id(core)
	var id := vertex_id(node)
	if core_id < 0 or id < 0:
		return false
	astar.set_point_disabled(id, true)
	var islanded := false
	for nb_id in astar.get_point_connections(id):
		if astar.is_point_disabled(nb_id):
			continue
		if astar.get_id_path(nb_id, core_id).is_empty():
			islanded = true
			break
	astar.set_point_disabled(id, false)
	return islanded


## Add `node` to the mirror. Called by AllocationSystem after `owned_by` is
## set. Idempotent.
func mirror_add(node: SkillNode) -> void:
	if _node_ids.has(node):
		return
	var id := astar.get_available_point_id()
	_node_ids[node] = id
	astar.add_point(id, node.global_position)
	for e in graph.get_edges():
		var other: SkillNode = null
		if e.from == node:
			other = e.to
		elif e.to == node:
			other = e.from
		else:
			continue
		var other_id := vertex_id(other)
		if other_id >= 0 and not astar.are_points_connected(id, other_id):
			astar.connect_points(id, other_id)


## Remove `node` from the mirror. Called by AllocationSystem before
## `owned_by` is cleared (so the is_cut check above sees current state).
## Idempotent.
func mirror_remove(node: SkillNode) -> void:
	var id: int = _node_ids.get(node, -1)
	if id < 0:
		return
	astar.remove_point(id)
	_node_ids.erase(node)


func _on_node_removed(node: SkillNode) -> void:
	mirror_remove(node)


func _on_edge_added(edge: Edge) -> void:
	var a := vertex_id(edge.from)
	var b := vertex_id(edge.to)
	if a < 0 or b < 0:
		return
	if not astar.are_points_connected(a, b):
		astar.connect_points(a, b)


func _on_edge_removed(edge: Edge) -> void:
	var a := vertex_id(edge.from)
	var b := vertex_id(edge.to)
	if a < 0 or b < 0:
		return
	if astar.are_points_connected(a, b):
		astar.disconnect_points(a, b)
