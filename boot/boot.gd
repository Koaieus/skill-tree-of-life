extends Node


func _ready():
	# Load settings, apply window options, etc.
	get_tree().change_scene("res://scenes/game_root.tscn")
