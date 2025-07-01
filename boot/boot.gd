extends Node


func _ready():
	var game_root_scene := preload("res://scenes/game_root.tscn")
	get_tree().change_scene_to_packed.call_deferred(game_root_scene)
