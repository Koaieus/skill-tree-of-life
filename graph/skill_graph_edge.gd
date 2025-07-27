@tool 
extends Line2D
class_name SkillGraphEdge

@export var node_a: SkillNode2D
@export var node_b: SkillNode2D
@export var length: float = -1

@onready var spring_joint: DampedSpringJoint2D = $DampedSpringJoint2D

var nodes: Array[SkillNode2D]:
	get(): return [node_a, node_b]
	set(v):
		assert(len(v)==2, "Invalid start/end node assignment to SkillGraphEdge, expected array of 2 elements, got %s" % len(v))
		assert(nodes.all(func(x): return x is SkillNode2D), "Start/end point missing: %s" % nodes)
		node_a = v[0]
		node_b = v[1]
		initialize()
		notify_property_list_changed()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#spring_joint.stiffness = 25.
	#spring_joint.damping = 0.61
	spring_joint.damping = 0.2 * sqrt(spring_joint.stiffness * 2.0)
	print('Damping: %s' % spring_joint.damping)
#	27, 0.61
	spring_joint.length = length if length >= 0 else node_a.global_position.distance_to(node_b.global_position)
	#spring_joint.rest_length = spring_joint.length * 0.5
	#spring_joint.rest_length = spring_joint.length * 0.8
	spring_joint.rest_length = spring_joint.length * 0.995
	initialize()
	update_position()
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	update_position()

func initialize() -> void:
	spring_joint.node_a = node_a.get_path()
	spring_joint.node_b = node_b.get_path()

func get_key() -> String:
	return _make_key(node_a, node_b)

func update_position() -> void:
	set_point_position(0, node_a.global_position)
	set_point_position(1, node_b.global_position)
	
## Generates a key for an edge that collides so that `get_key(AB) == get_key(BA)`
static func _make_key(a: SkillNode2D, b: SkillNode2D) -> String:
	var keys := [a.vertex_id, b.vertex_id]
	keys.sort()
	return "%s_%s" % keys
