@tool 
class_name TreeNode
extends GraphNode

signal allocated(entity: TreeEntity)
signal deallocated(previous_entity: TreeEntity)

@onready var owned_by: TreeEntity = null:
	get:
		return owned_by
	set(new_owner):
		var old_owner = owned_by
		if new_owner == owned_by:
			prints("Skip updating owner, no change:", old_owner, "->", new_owner)
			return
		owned_by = new_owner
		_on_update_owner(old_owner, new_owner)

@export var modifiers: Array[NumberStatModifier] = []

#@onready var button: Button = $Ports/ButtonBar/Button
@onready var icon: Control = %Icon
@onready var tool_tip: PackedScene = preload("res://gui/tooltip.tscn")

var _local_entities: Array[TreeEntity] = []

@export var local_entities: Array[TreeEntity]:
	get(): return _local_entities


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if _local_entities.size() == 1:
		owned_by = _local_entities[0]
	elif _local_entities.size() > 1:
		push_warning('Muliple TreeEntities as children of a single TreeNode')
		
	update_color()
	_hide_box_and_title()
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func get_neighbors() -> Array[TreeNode]:
	var arr = Array(
		(get_parent() as TreeGraphEdit).nav.astar.get_point_connections(get_instance_id())
	).map(instance_from_id)
	var nbs: Array[TreeNode]
	nbs.assign(arr)
	return nbs


func _on_update_owner(old_owner: TreeEntity, new_owner: TreeEntity) -> void:
	if old_owner:
		deallocate_from(old_owner)
	if new_owner:
		allocate_to(new_owner)
	else:
		clear_owner()


func allocate_to(entity: TreeEntity):
	prints(self, 'allocates to:', entity)
	update_color()
	if not entity._stats:
		print('can\'t allocate: no stats')
		return
	for mod in modifiers:
		entity._stats.add_stat_modifier(mod)
	allocated.emit(entity)
	
func deallocate_from(entity: TreeEntity):
	prints(self, 'deallocates from:', entity)
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
	if Global.player == owned_by:
		return # Already owned
		
	Global.player.allocate_skill_node(self)


func _on_child_entered_tree(node: Node) -> void:
	if node is TreeEntity:
		_local_entities.append(node)


func _on_child_exiting_tree(node: Node) -> void:
	if node is TreeEntity:
		if owned_by == node:
			push_warning('[Entity leaving tree] ToDo: maybe deallocate?')
			#node.deallocate_skill_node(self)
		_local_entities.erase(node)
