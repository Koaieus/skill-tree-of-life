class_name Skill extends Node2D

var links: Array[Skill] = []


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_pressed():
	print('Help help I\'m being oppressed!')

func get_connected_node_for_string(index: int) -> Node2D:
	return links[index].get_other_node(self)
