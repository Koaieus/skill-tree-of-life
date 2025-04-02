@tool
extends Node2D
class_name SkillTree


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_notify_local_transform(true)
	set_notify_transform(true)
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func update_links_between_skills() -> void:
	for child in get_children(true):
		pass
		#if child is Skill:
			#print('updating child', child)
			#child.update_link_positions()


func _on_property_list_changed() -> void:
	print('skilltree property list changed')
	#update_links_between_skills()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
			print('SkillTree received notification ', what)
		NOTIFICATION_TRANSFORM_CHANGED:
			print('SkillTree received notification ', what)
