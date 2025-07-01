@tool 
class_name TreeNode
extends GraphNode

signal allocated(entity: TreeEntity)
signal deallocated(previous_entity: TreeEntity)
signal local_entities_changed(entity_list: Array[TreeEntity])


## Tracks the TreeEntity this Skill node is currently allocated to
@onready var owned_by: TreeEntity = null:
	get:
		return owned_by
	set(new_owner):
		var old_owner = owned_by
		if new_owner != owned_by:
			owned_by = new_owner
			#_on_update_owner(old_owner, new_owner)

## List of StatModifiers offered by this skill node upon allocation
@export var modifiers: Array[NumberStatModifier] = []

## List of neighboring skill nodes
@export var neighbors: Array[TreeNode] = []

## Skill's icon to display
@onready var icon: Control = %Icon

## List of TreeEntities that are currently composed as children of this Skill Node
@export var local_entities: Array[TreeEntity] = []:
	get(): return local_entities
	
## Vision range, e.g. for fog-of-war mechanics; value in pixels (?)
@export var vision_range: int = 100

## Tooltip resource [preloaded]
@onready var tool_tip: PackedScene = preload("res://ui/tooltip.tscn")


## Point ID for use in A* implementation (internal value, only Navigator class should set this!)
var _vertex_id: int = -1

func get_vertex_id():
	return _vertex_id
## Setter function for `vertex_id`; private, not for skills or entities to change themselves
func _set_vertex_id(v):
	_vertex_id = max(v, -1)
	notify_property_list_changed()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_hide_box_and_title()
	compute_local_entities()
	update_color()


## Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#pass

func _recalculate_neighbors():
	neighbors.assign(
		Array(
			(get_parent() as TreeGraph).nav.astar.get_point_connections(get_instance_id())
		).map(instance_from_id)
	)

func add_neighbor(new_neighbor: TreeNode) -> void:
	if new_neighbor not in neighbors:
		neighbors.append(new_neighbor)

func remove_neighbor(neighbor_to_remove: TreeNode) -> void:
	neighbors.erase(neighbor_to_remove)

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
	for mod: StatModifier in modifiers:
		entity._stats.add_stat_modifier(mod)
	allocated.emit(entity)
	
func deallocate_from(entity: TreeEntity):
	prints('[ALLOCATION]:', self, 'deallocates from:', entity)
	update_color()
	if not entity._stats:
		return
	for mod in modifiers:
		entity._stats.remove_stat_modifier(mod)
	deallocated.emit(entity)

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
	if icon:
		icon.self_modulate = color
		print('color set to: ', color)
	else:
		print('cannot set color: no icon')

func _hide_box_and_title() -> void:
	var title_box: HBoxContainer = get_titlebar_hbox()
	var title_label: Label = title_box.get_child(0, true)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	if not Engine.is_editor_hint():
		self_modulate = Color.TRANSPARENT
		get_titlebar_hbox().hide()
		add_theme_constant_override("port_h_offset", size.x / 2)
		$M.add_theme_constant_override("margin_top", -title_box.size.y)
		$M.add_theme_constant_override("margin_bottom", -title_box.size.y)
		add_theme_constant_override("separation", -title_box.size.y)
	#icon.top_level = true
	

func _on_icon_mouse_entered() -> void:
	var tool_tip_instance: ToolTip = tool_tip.instantiate()
	tool_tip_instance.hide()
	tool_tip_instance.target = self
	print_debug(self.size)
	tool_tip_instance.position = self.get_global_transform_with_canvas().origin + Vector2(size.x + 10, 0)
	tool_tip_instance.title = title
	var lines: Array[String] = []
	for modifier in modifiers:
		if not modifier:
			continue
		lines.append(modifier.as_string())
	tool_tip_instance.set_lines(lines)
	tool_tip_instance.valid = true
	add_child(tool_tip_instance)
	await get_tree().create_timer(0.3).timeout
	if has_node("ToolTip") and get_node('ToolTip').valid:
		get_node('ToolTip').show()

func _on_icon_mouse_exited() -> void:
	get_node('ToolTip').queue_free()


func _on_icon_pressed() -> void:
	if Game.player == owned_by:
		return # Already owned
		
	# ToDo: replace with emitting one of Game's signals
	#allocate_to(Game.player)
	Game.player.allocate_skill_node(self)


#func _on_child_entered_tree(node: Node) -> void:
	#if node is TreeEntity:
		#local_entities.append(node)
		#local_entities_changed.emit(local_entities)
#
#
#func _on_child_exiting_tree(node: Node) -> void:
	#if node is TreeEntity:
		#if owned_by == node:
			#push_warning('[Entity leaving tree] ToDo: maybe deallocate?')
			##node.deallocate_skill_node(self)
		#local_entities.erase(node)
		#local_entities_changed.emit(local_entities)

func compute_local_entities():
	local_entities.clear()
	for node in get_children():
		if node is TreeEntity and node not in local_entities:
			local_entities.append(node)
	if local_entities:
		handle_local_entities()

## Checks list of TreeEntity children and maybe update owner accordingly
func handle_local_entities():
	#if local_entities.size() == 1:
		#owned_by = local_entities[0]
	#el
	if local_entities.size() > 1:
		push_error('Multiple TreeEntities as children of a single TreeNode')
		
