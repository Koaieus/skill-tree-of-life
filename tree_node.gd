@tool 
class_name TreeNode
extends GraphNode

@export var owned_by: TreeEntity:
	get:
		return owned_by
	set(value):
		owned_by = value
		update_owner(value)

@export var modifiers: Array[NumberStatModifier] = []

#@onready var button: Button = $Ports/ButtonBar/Button
@onready var icon = $C/Icon
@onready var tool_tip: PackedScene = preload("res://tooltip.tscn")

var mod_scene_packed = preload("res://mod.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	update_owner(owned_by)
	#self_modulate = Color.TRANSPARENT
	#icon.top_level = true
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	


func update_owner(new_owner: TreeEntity):
	if not new_owner:
		clear_owner()
		return
	set_color(new_owner.color)
		
func clear_owner():
	set_color(Color.WHITE)

func set_color(color: Color):
	if icon:
		icon.self_modulate = color

func add_new_mod() -> void:
	var new_mod := mod_scene_packed.instantiate()
	add_child(new_mod)


func _on_tree_entered() -> void:
	pass


func _on_icon_mouse_entered() -> void:
	var tool_tip_instance: ToolTip = tool_tip.instantiate()
	tool_tip_instance.hide()
	tool_tip_instance.target = self
	tool_tip_instance.position = self.get_global_transform_with_canvas().origin - Vector2(300, 0)
	tool_tip_instance.title = title
	tool_tip_instance.valid = true
	add_child(tool_tip_instance)
	await get_tree().create_timer(0.3).timeout
	if has_node("ToolTip") and get_node('ToolTip').valid:
		get_node('ToolTip').show()

func _on_icon_mouse_exited() -> void:
	get_node('ToolTip').queue_free()
