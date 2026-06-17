class_name SkillBlade
extends Node2D

@export var owned_by: Entity

@onready var _edges_node: Node = $Edges

const BLADE_NODE = preload("res://attack/melee/blade_node.tscn")
const BLADE_EDGE = preload("res://attack/melee/blade_edge.tscn")

var _blade_nodes: Array[BladeNode] = []
var _pivot: BladeNode = null


func _ready() -> void:
	for child in get_children():
		if child is BladeNode:
			_blade_nodes.append(child)
			if child.is_pivot:
				_pivot = child
	for edge in _edges_node.get_children():
		if edge is BladeEdge and edge.from != null and edge.to != null:
			_create_joint(edge.from, edge.to)


func add_blade_node(pos: Vector2, pivot: bool = false) -> BladeNode:
	var node := BLADE_NODE.instantiate() as BladeNode
	node.position = pos
	node.is_pivot = pivot
	add_child(node)
	_blade_nodes.append(node)
	if pivot:
		_pivot = node
	return node


func add_edge(from: BladeNode, to: BladeNode) -> BladeEdge:
	var edge := BLADE_EDGE.instantiate() as BladeEdge
	edge.from = from
	edge.to = to
	_edges_node.add_child(edge)
	edge.area_entered.connect(_on_edge_area_entered.bind(edge))
	_create_joint(from, to)
	return edge


func _create_joint(from: BladeNode, to: BladeNode) -> void:
	var joint := PinJoint2D.new()
	joint.position = from.position
	add_child(joint)
	joint.node_a = joint.get_path_to(from)
	joint.node_b = joint.get_path_to(to)


## Sweep the entire blade one full revolution around the pivot.
## duration: total time in seconds. Uses sine ease-in-out for an s-curve feel.
func swing(duration: float = 1.2) -> void:
	if _pivot == null:
		push_error("SkillBlade.swing: no pivot node")
		return

	var pivot_world := _pivot.global_position
	var pivot_local := _pivot.position
	var start_rot := rotation

	_set_dynamic_freeze(true)

	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_method(func(frac: float) -> void:
		var angle := start_rot + frac * TAU
		rotation = angle
		# Keep pivot's world position fixed while SkillBlade rotates.
		# pivot_world = global_position + pivot_local.rotated(rotation)
		# → global_position = pivot_world - pivot_local.rotated(angle)
		global_position = pivot_world - pivot_local.rotated(angle)
	, 0.0, 1.0, duration)

	await tween.finished
	_set_dynamic_freeze(false)


func _set_dynamic_freeze(frozen: bool) -> void:
	for node in _blade_nodes:
		if node.is_pivot:
			continue
		node.freeze = frozen
		if frozen:
			node.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC


func _on_edge_area_entered(area: Area2D, _edge: BladeEdge) -> void:
	print("BladeEdge hit: ", area.name)
