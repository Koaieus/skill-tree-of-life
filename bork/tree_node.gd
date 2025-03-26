@tool 
class_name TreeNode
extends GraphNode

var mod_scene_packed = preload("res://bork/mod.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func add_new_mod() -> void:
	var new_mod := mod_scene_packed.instantiate()
	add_child(new_mod)
