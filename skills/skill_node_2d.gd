@tool 
extends RigidBody2D
class_name SkillNode2D

signal allocated(node: TreeNode, entity: TreeEntity)
signal deallocated(node: TreeNode, previous_entity: TreeEntity)
signal local_entities_changed(entity_list: Array[TreeEntity])

signal pressed
signal right_pressed
signal hovered
signal position_changed(new_pos: Vector2)

var _last_pos: Vector2

## Tracks the TreeEntity this Skill node is currently allocated to
var owned_by: TreeEntity = null
@export var skill_data: SkillData:
	set(v):
		skill_data = v
		_initialize()

## Icon sprite node
@onready var sprite_2d: Sprite2D = $Sprite2D
## Skill's center marker node
@onready var marker: Marker2D = $Marker2D

@onready var debug_label: Label = $DebugLabel
@onready var debug_label2: Label = $DebugLabel2

## List of neighboring skill nodes
@export var neighbors: Array[SkillNode2D]

### Tooltip resource [preloaded]
#@onready var tool_tip: PackedScene = preload("res://ui/tooltip.tscn")


## Point ID for use in A* implementation (internal value, only Navigator class should set this!)
var vertex_id: int = -1:
	get = get_vertex_id,
	set = set_vertex_id

func get_vertex_id(): return vertex_id
func set_vertex_id(v):
	vertex_id = max(v, -1)
	notify_property_list_changed()

const USE_PHYSICS := true

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if USE_PHYSICS:
		set_notify_transform(true)
	else:
		set_notify_transform(false)
		set_physics_process(false)
		
	_last_pos = global_position
	
	if skill_data.icon:
		sprite_2d.texture = skill_data.icon

func _process(delta: float) -> void:
	if debug_label:
		debug_label.text = "m=%.2f" % mass
	if debug_label2:
		debug_label2.text = "Zzz" if sleeping else ""
	
func _physics_process(delta):
	if USE_PHYSICS and global_position != _last_pos:
		position_changed.emit(global_position)
		_last_pos = global_position
		
func _initialize() -> void:
	assert(skill_data is SkillData, 'Cannot initialize skill %s: No skill data')
	
	if skill_data.is_starter_node:
		print('Found Starting Skill Node: %s' % self)
		add_to_group(&"starter-skills")

#func _recalculate_neighbors():
	#assert(false, 'TODO: Move to astar or treegraph or anything but here')
	#neighbors.assign(
		#Array(
			#(get_parent() as SkillGraphWorld).nav.astar.get_point_connections(get_instance_id())
		#).map(instance_from_id) # TODO: use vertex ID
	#)
#
#func add_neighbor(new_neighbor: TreeNode) -> void:
	#assert(new_neighbor is TreeNode)
	#if new_neighbor not in neighbors:
		#neighbors.append(new_neighbor)
#
#func remove_neighbor(neighbor_to_remove: TreeNode) -> void:
	#neighbors.erase(neighbor_to_remove)

#func _on_update_owner(old_owner: TreeEntity, new_owner: TreeEntity) -> void:
	#if old_owner:
		#deallocate_from(old_owner)
	#if new_owner:
		#allocate_to(new_owner)
	#else:
		#clear_owner()


func allocate_to(entity: TreeEntity):
	prints('[ALLOCATION]:', self, 'allocates to:', entity)
	owned_by = entity
	update_color()
	if not entity._stats:
		print('[ALLOCATION]: can\'t allocate: no stats')
		return
	for mod: StatModifier in skill_data.modifiers:
		entity._stats.add_stat_modifier(mod)
	allocated.emit(self, entity)
	
func deallocate_from(entity: TreeEntity):
	prints('[ALLOCATION]:', self, 'deallocates from:', entity)
	update_color()
	if not entity._stats:
		return
	for mod in skill_data.modifiers:
		entity._stats.remove_stat_modifier(mod)
	deallocated.emit(self, entity)

func clear_owner():
	update_color()

func has_owner() -> bool:
	return owned_by != null

func update_color():
	if has_owner():
		set_color(owned_by.color)
	else:
		set_color(Color.WHITE)


func set_color(color: Color):
	self_modulate = color
	print('color set to: ', color)
	
func get_center() -> Vector2:
	assert(marker, 'No center marker')
	return marker.global_position

func _input_event(viewport: Viewport, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and (event as InputEventMouse).is_pressed():
		if event.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			#Game.node_pressed_right.emit(self)
			right_pressed.emit()


#func _on_icon_pressed() -> void:
	#if Game.player == owned_by:
		#return # Already owned
		#
	## ToDo: replace with emitting one of Game's signals
	##allocate_to(Game.player)
	#Game.player.allocate_skill_node(self)
