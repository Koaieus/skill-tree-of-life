class_name PlayerInputController
extends Node

## Routes SkillNode clicks to AllocationSystem on behalf of a single Player
## entity. Listens to Graph.node_added so runtime-spawned (procgen) nodes
## wire themselves up automatically.
##
## A single-player handler is enough for the MVP. Multi-entity selection
## (per-entity cores, hot-seat) would replace `player` with a selection
## strategy without changing the click-dispatch shape.

@export var graph: Graph
@export var allocation_system: AllocationSystem
@export var player: Entity


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if graph == null or allocation_system == null or player == null:
		push_warning("PlayerInputController missing a reference; clicks won't route")
		return
	graph.node_added.connect(_on_node_added)
	for sn in graph.get_skill_nodes():
		_on_node_added(sn)


func _on_node_added(skill_node: SkillNode) -> void:
	if not skill_node.clicked.is_connected(_on_skill_node_clicked):
		skill_node.clicked.connect(_on_skill_node_clicked)


func _on_skill_node_clicked(skill_node: SkillNode) -> void:
	if skill_node.owned_by == null:
		allocation_system.allocate(skill_node, player)
	elif skill_node.owned_by == player:
		allocation_system.deallocate(skill_node)
