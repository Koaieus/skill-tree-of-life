@tool 
extends Line2D
class_name SkillGraphEdge


var _nodes: Array[SkillNode2D] = [null, null]

var nodes: Array[SkillNode2D]:
	get(): return Array(_nodes)
	set(v):
		assert(
			len(v)==2, 
			"Invalid start/end node assignment to SkillGraphEdge, expected array of 2 elements, got %s" % len(v)
		)
		_validate_nodes(v)
		_set_node(v[0], 0)
		_set_node(v[1], 1)
		notify_property_list_changed()
		
@export var node_a: SkillNode2D:
	get(): return _nodes[0]
	set(v): _set_node(v, 0)

@export var node_b: SkillNode2D:
	get(): return _nodes[1]
	set(v): _set_node(v, 1)

var _conn_refs: Array[Variant] = [null, null]

## Spring constant
@export_range(0.1, 130., 0.1) var stiffness: float = 50.
@export var dead_zone: float = 10.
@export var rest_length: float = -1
@export_range(0.1, 3., 0.1, 'unit:s') var settle_time: float = 1.0

var damping_crit: float:
	get():
		return (
			2. * sqrt(stiffness * (node_a.mass + node_b.mass)) 
			if (node_a and node_b) else 0.
		)

@onready var spring_joint: DampedSpringJoint2D = $DampedSpringJoint2D

const MINIMUM_FORCE: float = 10. # min force to apply
@export_range(0., 2., 0.05) var ZETA: float = 1.0  # Crit Damping factor, <1 underdamped, 1=crit, >1 overdamped

const REST_LENGTH_FACTOR: float = 1.0
const MIN_REST_LENGTH: float = 150.


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	update_position()
	set_physics_process(true)  # start active
	_init_rest_length()

func _physics_process(delta: float) -> void:
	if node_a and node_b: 
		apply_spring_force(delta)
		return
	#set_physics_process(false)

func _process(delta: float) -> void:
	default_color = Color.WHEAT if is_physics_processing() else Color.DARK_SLATE_BLUE

func _set_node(new_node: SkillNode2D, idx: int) -> void:
	if new_node != _nodes[idx]:
		_connect_node_position_update(new_node, idx)
		#_on_body_sleep_toggled()
		_nodes[idx] = new_node
		notify_property_list_changed()

func _init_rest_length() -> void:
	if rest_length < 0 and node_a and node_b:
		# Rest length not specified, calculate based on position
		var dir = node_b.global_position - node_a.global_position
		rest_length = dir.length() * REST_LENGTH_FACTOR
		rest_length = maxf(rest_length, MIN_REST_LENGTH)
		print('Set rest length: %s' % [rest_length])

func apply_spring_force(delta: float) -> void:
	assert(node_a and node_b)
	# Skip if both bodies are asleep
	if node_a.is_sleeping() and node_b.is_sleeping():
		set_physics_process(false)
		return

	# Compute displacement vector
	var dir := node_b.global_position - node_a.global_position
	var dist := dir.length()
	var unit := dir.normalized()
	# For a 2% settling criterion: Ts ≈ 4 / (ζ * ωₙ)
	# Choose damping ratio ζ ≈ 1 (critical)
	var omega_n = 4.0 / settle_time # time in seconds
	## PARAMETERS
	## Mass
	var m    = node_a.mass + node_b.mass
	## Spring constant
	var k    = omega_n * omega_n   # since ωₙ = sqrt(k/m)   
	## Damping constant
	var damping_crit: float = 2.0 * sqrt(k * m) 
	var c    = damping_crit * ZETA
	#var c    = damping_crit * (ZETA + ProjectSettings.get_setting('physics/2d/default_linear_damp'))          
	## Dead zone, e.g. 10 pixels tolerance
	var dead = dead_zone        

	# Compute force magnitude based on a “dead zone” potential:
	var displacement = dist
	if dist > rest_length + dead:
		displacement -= rest_length + dead
	elif dist < rest_length - dead:
		displacement -= rest_length - dead
	else:
		return  # within dead zone: no force
	
	## Push radius
	#if dist < PUSH_RADIUS and dist > 0:
		#var strength := (PUSH_RADIUS - dist) / PUSH_RADIUS * MAX_PUSH_FORCE
		## apply equal and opposite
		#node_a.apply_central_force(-unit * strength)
		#node_b.apply_central_force(unit * strength)
		#print('Applying PUSH dist=%s => strength=%s' % [dist, strength])
		#set_physics_process(true)
		#return

	# Compute relative velocity along the axis
	var rel_vel = (node_b.linear_velocity - node_a.linear_velocity).dot(unit)
	const MAX_REL_VEL := 300.0
	rel_vel = clamp(rel_vel, -MAX_REL_VEL, MAX_REL_VEL)
	# Hooke’s law + damping
	var force_magnitude: float = -k * displacement - c * rel_vel
	
	if absf(force_magnitude) >= MINIMUM_FORCE:
		var force: Vector2 = unit * force_magnitude
		node_a.apply_central_force(-force)
		node_b.apply_central_force(force)
		#print('Applying rel_vel=%s => force=%s' % [rel_vel, force])
		set_physics_process(true)
		



func update_position() -> void:
	if node_a and node_b:
		set_point_position(0, node_a.global_position)
		set_point_position(1, node_b.global_position)

func get_key() -> String:
	var n = nodes
	_validate_nodes(n)
	return _make_key.callv(n)

func _validate_nodes(nodes_: Array[SkillNode2D]) -> void:
	assert(nodes_.all(func(x): return x is SkillNode2D), "Start/end node missing (a, b): %s" % [nodes_])

## Generates a key for an edge that collides so that `get_key(AB) == get_key(BA)`
static func _make_key(a: SkillNode2D, b: SkillNode2D) -> String:
	var keys := [a.vertex_id, b.vertex_id]
	keys.sort()
	return "%s_%s" % keys


func _connect_node_position_update(node: SkillNode2D, point_index: int):
	var position_change_bind: Variant = _conn_refs[point_index]

	var old_node: SkillNode2D = _nodes[point_index]
	if old_node and position_change_bind is Callable:
		## Unsubscribe existing
		# Sleeping state
		old_node.sleeping_state_changed.disconnect(_on_body_sleep_toggled)
		# Position change
		old_node.item_rect_changed.disconnect(position_change_bind)
		_conn_refs[point_index] = null

	# Subscribe (and Like)
	assert(node is SkillNode2D)
	if node:
		# Sleeping state
		node.sleeping_state_changed.connect(_on_body_sleep_toggled)
		# Position change
		#position_change_bind = _on_node_position_change as Callable
		position_change_bind = _on_node_position_change.bind(point_index) as Callable
		node.position_changed.connect(position_change_bind)
		_conn_refs[point_index] = position_change_bind
		
		prints("Connected %s to %s [%s]" % [position_change_bind, node, point_index])

func _on_body_sleep_toggled() -> void:
	#print('Sleep toggled of body of %s ' % [self])
	if node_a and node_b:
		set_physics_process(true)
		#set_physics_process(node_a.is_sleeping() or node_b.is_sleeping())
	
func _on_node_position_change(new_position: Vector2, point_index: int) -> void:
	set_point_position(point_index, new_position)
