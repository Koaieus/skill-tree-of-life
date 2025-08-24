extends Node2D
class_name SkillGraphWorld

# Vertex signals (skill nodes)
signal node_added(node: SkillNode2D)
signal node_removed(node: SkillNode2D)
signal node_allocated(node: SkillNode2D, entity: TreeEntity)
signal node_hovered(node: SkillNode2D)

# Edge signals (skill connections)
signal connection_made(from: SkillNode2D, to: SkillNode2D)
signal connection_removed(from: SkillNode2D, to: SkillNode2D)


@onready var camera: Camera2D = $Camera2D

@onready var players: Node = $Players
@onready var entities: Node = $Entities

@onready var edge_layer: Node2D = $EdgeLayer
@onready var node_layer: Node2D = $NodeLayer
@onready var fx_layer: Node2D = $FXLayer
@onready var debug_layer: CanvasLayer = $DebugLayer

@export var dragging: SkillNode2D = null

## Internal skill node map for quick lookups
var node_map: Dictionary[StringName, SkillNode2D] = {} # StringName -> SkillNode2D
## Internal skill-skill edge (connection) map for quick lookups
var edge_map: Dictionary[StringName, SkillGraphEdge] = {}

# Optional back-reference to the SkillGraphEdit used to generate this
var source_editor_graph: Node = null

func _ready():
	camera.make_current()  # Take control on load
	#camera.zoom = Vector2.ONE * 0.5  # Start zoomed out (tweak to taste)

	print_debug("SkillGraphWorld ready.")
	# Optional: call some deferred initialization
	# call_deferred("_initialize_world")
	
func _physics_process(delta: float) -> void:
	if dragging:
		var dragging_vector := get_global_mouse_position() - dragging.global_position
		var dist := dragging_vector.length()
		const force_factor: float = 10.
		dragging.apply_central_force(dragging_vector.normalized() * dist * force_factor)

func add_skill_node_from_skill_data(name: StringName, position: Vector2, data: SkillData) -> SkillNode2D:
	var node: SkillNode2D = preload("res://skills/skill_node_2d.tscn").instantiate()
	node.name = name
	node.skill_data = data
	node.global_position = position
	node_layer.add_child(node)
	initialize_node(node)  # Wire up signals etc.
	
	node_map[node.name] = node
	Game.navigator._add_point(node)
	
	return node

func connect_nodes(from_node: SkillNode2D, to_node: SkillNode2D) -> void:
	var nodes := [from_node, to_node]
	assert(from_node and to_node, "Missing nodes for edge: %s <-> %s" % nodes)
	assert(SkillGraphEdge._make_key(from_node, to_node) not in edge_map, "Edge between %s and %s already exists!" % nodes)
	
	# Make new Edge instance
	var edge: SkillGraphEdge = preload("res://graph/skill_graph_edge.tscn").instantiate()
	#edge.nodes = nodes
	edge.node_a = from_node
	edge.node_b = to_node
	# Add edge to edge layer 
	edge_layer.add_child(edge)
	# Update registry
	edge_map[edge.get_key()] = edge
	
	
func clear_world():
	node_map.clear()
	for layer: Node in [node_layer, edge_layer, fx_layer]:
		for node in layer.get_children():
			node.queue_free()
	
func highlight_path(path: Array[SkillNode2D]) -> void:
	# optional helper for showing A* result
	for i in range(path.size() - 1):
		var a = node_map.get(path[i])
		var b = node_map.get(path[i + 1])
		if not a or not b:
			continue
		var fx = Line2D.new()
		fx.width = 6.0
		fx.default_color = Color.YELLOW
		fx.add_point(a.global_position)
		fx.add_point(b.global_position)
		fx_layer.add_child(fx)

func get_node_by_id(id: StringName) -> Node2D:
	return node_map.get(id)

func _on_node_hovered(node: SkillNode2D) -> void:
	print("Node %s hovered" % [node])

func _on_node_pressed(node: SkillNode2D) -> void:
	print("Node %s pressed" % [node])

func _on_node_right_pressed(node: SkillNode2D) -> void:
	print("Node %s right pressed" % [node])
	dragging = node
	print('Start dragging %s' % [dragging])
	
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouse).is_released():
		if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_MASK_RIGHT:
			if dragging:
				dragging = null
	
	if event.is_action_pressed("ui_left"):
		#camera.move_local_x()
		pass

## Adds a new TreeEntity to the skill graph on given core node, allocates skill too
func add_entity(entity: TreeEntity, core: SkillNode2D) -> void:
	assert(core.owned_by == null, 'Designated core for %s is already owned by %s' % [entity, core.owned_by])
	assert(entity.core == null, 'Cannot designate %s as core for new entity `%s`: entity already has core `%s`' % [core, entity, entity.core])
	assert(core is SkillNode2D, 'Missing core')
	entity.core = core
	core.allocate_to(entity)
	

## Wires up node, after it has been added
func initialize_node(node: SkillNode2D) -> void:
	print('Initializing %s' % node)
	node.hovered.connect(_on_node_hovered.bind(node))
	node.pressed.connect(_on_node_pressed.bind(node))
	#node.right_pressed.connect(_on_node_right_pressed.bind(node))
	node.right_pressed.connect(func(): _on_node_right_pressed(node))
