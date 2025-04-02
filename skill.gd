@tool
class_name Skill extends Node2D

signal transform_changed

var links: Array[Edge] = []


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_notify_transform(true)
	update_link_positions()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_pressed():
	print('Help help I\'m being oppressed!')

func get_connected_node_for_link_idx(index: int) -> Node2D:
	return links[index].get_other_node(self)

func get_connected_skills() -> Array[Skill]:
	return links.map(func(edge): edge.get_other_node())

func update_link_positions():
	print('updating positions')
	for link in links:
		link.update_position()
		#link.notify_property_list_changed()


func _on_property_list_changed() -> void:
	print('on_prop_list_changed')
	update_link_positions()
