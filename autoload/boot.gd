extends Node


const FIRST_LEVEL_SANDBOX = preload("res://scenes/first_level_sandbox.tscn")


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Check if this is a production/exported release build
	if OS.has_feature("release"):
		
		var first_level_sandbox := FIRST_LEVEL_SANDBOX.instantiate() as GameRoot
		var procgen_config := first_level_sandbox.get('preset') as GraphProcgenConfig
		if procgen_config:
			procgen_config.seed = 0
		# Switch to the first level sandbox
		get_tree().change_scene_to_node(first_level_sandbox)
