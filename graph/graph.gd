@tool
class_name Graph
extends Node2D

## The battlefield. Holds SkillNodes (under `skill_nodes_container`) and Edges
## (under `edges_container`), plus a Navigator that mirrors structural state
## as an AStar view. Scenes built from this class are intended to be loaded
## as levels — procgen builds the contents, then the result is instanced
## under the game's level layer.
##
## Decoupling: Graph emits structural signals; Navigator, AllocationSystem,
## renderers, and AIs listen. Graph itself never reaches into the AStar or
## the entity stat boards.

signal node_added(skill_node: SkillNode)
signal node_removed(skill_node: SkillNode)
signal edge_added(edge: Edge)
signal edge_removed(edge: Edge)

## Where dynamically-spawned [Entity] instances live (procgen, scripted setup).
## Parallel to the other containers — Graph owns the slot, GameRoot owns the
## spawning API. Hand-authored entities (dev_sandbox) may live elsewhere; the
## `%Player` unique-name lookup ignores parent.

@onready var navigator: Navigator = $Navigator
@onready var entities_container: Node = $Entities
@onready var skill_nodes_container: Node2D = $Nodes
@onready var edges_container: Node2D = $Edges

# Adjacency index for get_neighbours. Rebuilt lazily whenever either container
# gains or loses a child, so it stays correct for procgen, remove_skill_node,
# and any direct add_child. Not used in the editor: an inspector edit to
# `Edge.from` / `Edge.to` mutates topology without touching the child lists,
# and no editor path is hot enough to care.
var _adjacency: Dictionary[SkillNode, Array] = {}
var _adjacency_dirty: bool = true


func _ready() -> void:
	for c: Node in [skill_nodes_container, edges_container]:
		c.child_entered_tree.connect(_mark_adjacency_dirty.unbind(1))
		c.child_exiting_tree.connect(_mark_adjacency_dirty.unbind(1))
	if Engine.is_editor_hint():
		return
	# Re-emit signals for content already authored into the scene so
	# late-bound listeners (Navigator, UI) can build their initial state
	# uniformly with the procgen-add-at-runtime path.
	for sn in get_skill_nodes():
		node_added.emit(sn)
	for e in get_edges():
		edge_added.emit(e)


func get_skill_nodes() -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	if skill_nodes_container == null:
		return out
	for c in skill_nodes_container.get_children():
		if c is SkillNode:
			out.append(c)
	return out


func get_edges() -> Array[Edge]:
	var out: Array[Edge] = []
	if edges_container == null:
		return out
	for c in edges_container.get_children():
		if c is Edge:
			out.append(c)
	return out


## Direct neighbours of [param node] — every other endpoint that shares an
## edge with it. Reads a cached adjacency index, no AStar dependency, so it
## works in editor context (spell playground, validation).
##
## Hot path: the vision system's sensed traversal calls this once per pop, so
## it must not be O(edges). Returns a fresh array — callers may mutate it.
func get_neighbours(node: SkillNode) -> Array[SkillNode]:
	if edges_container == null or node == null:
		return [] as Array[SkillNode]
	if Engine.is_editor_hint():
		# Inspector edits to `Edge.from` / `Edge.to` don't dirty the index.
		var adj: Array = _build_adjacency().get(node, [])
		return adj.duplicate()
	if _adjacency_dirty:
		_adjacency = _build_adjacency()
		_adjacency_dirty = false
	var cached: Array = _adjacency.get(node, [])
	return cached.duplicate()


func _mark_adjacency_dirty() -> void:
	_adjacency_dirty = true


## One pass over the edges, appending each endpoint to the other's list. Order
## within a node's list matches edge child order, as the old per-node walk did.
func _build_adjacency() -> Dictionary[SkillNode, Array]:
	var adj: Dictionary[SkillNode, Array] = {}
	for n in get_skill_nodes():
		adj[n] = [] as Array[SkillNode]
	for e in get_edges():
		if e.from == null or e.to == null:
			continue
		# Self-loop: per graph theory each endpoint counts independently, so a
		# single self-loop edge contributes the node itself twice (degree +2).
		# Consumers that BFS already dedupe via their own visited sets; this
		# keeps spell propagation (FanAllStep etc.) consistent with the
		# "self-loop weaponisable by SUM merger" mechanic. See Resonator.
		if e.from == e.to:
			if adj.has(e.from):
				adj[e.from].append(e.from)
				adj[e.from].append(e.from)
			continue
		if adj.has(e.from):
			adj[e.from].append(e.to)
		if adj.has(e.to):
			adj[e.to].append(e.from)
	return adj


func add_skill_node(node: SkillNode) -> void:
	skill_nodes_container.add_child(node)
	node_added.emit(node)


func remove_skill_node(node: SkillNode) -> void:
	# Connected edges removed first so the Navigator sees a consistent
	# graph state at every signal step.
	for e in get_edges():
		if e.from == node or e.to == node:
			remove_edge(e)
	skill_nodes_container.remove_child(node)
	node_removed.emit(node)
	node.queue_free()

const EDGE = preload("res://graph/edge.tscn")

func add_edge(from: SkillNode, to: SkillNode) -> Edge:
	var edge := EDGE.instantiate() as Edge
	edge.from = from
	edge.to = to
	edges_container.add_child(edge)
	edge_added.emit(edge)
	return edge


func remove_edge(edge: Edge) -> void:
	if edge.from != null:
		edge.from.self_loops.erase(edge)
	edges_container.remove_child(edge)
	edge_removed.emit(edge)
	edge.queue_free()
