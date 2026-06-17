class_name SkillBlade
extends Node2D

## A Phantom blade created as a 1:1 scale copy of an induced subgraph of SkillNodes
## To be used as a one-off melee attack, with edges/vertices having a damaging hitbox


@export var owned_by: Entity

@onready var edges: Node = $Edges

const BLADE_NODE = preload("res://attack/melee/blade_node.tscn")
const BLADE_EDGE = preload("res://attack/melee/blade_edge.tscn")


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func add_edge(from: BladeNode, to: BladeNode) -> void:
	var edge := BLADE_EDGE.instantiate() as BladeEdge
	edge.from = from
	edge.to = to
	# wire edge signals e.g. collision with 
	edge.body_shape_entered.connect(_on_body_shape_entered)
	
func _on_body_shape_entered(body_rid: RID, body: Node2D, body_shape_index: int, local_shape_index: int) -> void:
	print('Shape entered', body_rid, body, body_shape_index, local_shape_index)
