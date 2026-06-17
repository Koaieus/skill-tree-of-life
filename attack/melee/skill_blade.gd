class_name SkillBlade
extends Node2D

## Emitted whenever a blade element overlaps an enemy SkillNode during a swing.
## hitter is the BladeEdge or BladeNode that made contact.
## Callers (BattleSystem, Events) subscribe here; SkillBlade does not know about
## damage routing — it only collects and re-emits.
signal hit(hitter: Node2D, target: SkillNode, damage: float)

@export var owned_by: Entity

@onready var _edges_node: Node = $Edges

const BLADE_NODE = preload("res://attack/melee/blade_node.tscn")
const BLADE_EDGE = preload("res://attack/melee/blade_edge.tscn")

const EDGE_DAMAGE: float = 1.0
const NODE_DAMAGE: float = 1.0

var _blade_nodes: Array[BladeNode] = []
var _pivot: BladeNode = null
# Per-element hit dedup: element → {SkillNode: true}. Cleared at swing start.
var _hits_this_swing: Dictionary = {}


func _ready() -> void:
	for child in get_children():
		if child is BladeNode:
			_register_blade_node(child)
	for edge in _edges_node.get_children():
		if edge is BladeEdge and edge.from != null and edge.to != null:
			_create_joint(edge.from, edge.to)
			edge.area_entered.connect(_on_edge_area_entered.bind(edge))


func add_blade_node(pos: Vector2, pivot: bool = false) -> BladeNode:
	var node := BLADE_NODE.instantiate() as BladeNode
	node.position = pos
	node.is_pivot = pivot
	add_child(node)
	_register_blade_node(node)
	return node


func add_edge(from: BladeNode, to: BladeNode) -> BladeEdge:
	var edge := BLADE_EDGE.instantiate() as BladeEdge
	edge.from = from
	edge.to = to
	_edges_node.add_child(edge)
	edge.area_entered.connect(_on_edge_area_entered.bind(edge))
	_create_joint(from, to)
	return edge


func _register_blade_node(node: BladeNode) -> void:
	_blade_nodes.append(node)
	if node.is_pivot:
		_pivot = node
	node.hitbox.area_entered.connect(_on_node_area_entered.bind(node))


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

	_hits_this_swing.clear()
	_set_dynamic_freeze(true)

	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_method(func(frac: float) -> void:
		var angle := start_rot + frac * TAU
		rotation = angle
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


func _on_edge_area_entered(area: Area2D, edge: BladeEdge) -> void:
	if _is_valid_target(area) and _record_hit(edge, area as SkillNode):
		hit.emit(edge, area as SkillNode, EDGE_DAMAGE)


func _on_node_area_entered(area: Area2D, node: BladeNode) -> void:
	if _is_valid_target(area) and _record_hit(node, area as SkillNode):
		hit.emit(node, area as SkillNode, NODE_DAMAGE)


func _is_valid_target(area: Area2D) -> bool:
	if not area is SkillNode:
		return false
	var sn := area as SkillNode
	return sn.is_allocated() and (owned_by == null or sn.owned_by != owned_by)


func _record_hit(element: Node2D, target: SkillNode) -> bool:
	if not _hits_this_swing.has(element):
		_hits_this_swing[element] = {}
	var seen: Dictionary = _hits_this_swing[element]
	if seen.has(target):
		return false
	seen[target] = true
	return true
