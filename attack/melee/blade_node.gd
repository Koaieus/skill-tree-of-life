@tool
class_name BladeNode
extends Area2D

@export_range(1.0, 100., 1.0) var radius: float = 32.0
@export var is_pivot: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_notify_transform(true)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _to_string() -> String:
	return "<BladeNode>"
