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


func _ready() -> void:
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
## edge with it. Walks edges, no AStar dependency, so it works in editor
## context (spell playground, validation).
func get_neighbours(node: SkillNode) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	if edges_container == null or node == null:
		return out
	for e in get_edges():
		if e.from == null or e.to == null:
			continue
		# Self-loop: per graph theory each endpoint counts independently, so a
		# single self-loop edge contributes the node itself twice (degree +2).
		# Consumers that BFS already dedupe via their own visited sets; this
		# keeps spell propagation (FanAllStep etc.) consistent with the
		# "self-loop weaponisable by SUM merger" mechanic. See Resonator.
		if e.from == node and e.to == node:
			out.append(node)
			out.append(node)
		elif e.from == node:
			out.append(e.to)
		elif e.to == node:
			out.append(e.from)
	return out


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
