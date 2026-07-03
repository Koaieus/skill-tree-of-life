@tool
class_name CapacityPip
extends ColorRect
## A single rotated-diamond pip. Leaf element instanced N times by
## CapacityBlips — not usually placed standalone, but self-contained and
## @tool so it previews correctly on its own too.

@export var filled: bool = false:
	set(v):
		filled = v
		_push(&"filled", 1.0 if v else 0.0)

@export var highlighted: bool = false:
	set(v):
		highlighted = v
		_push(&"highlight", 1.0 if v else 0.0)

@export var fill_color: Color = Color(0.62, 0.21, 0.21, 1.0):
	set(v):
		fill_color = v
		_push(&"fill_color", v)

@export var empty_color: Color = Color(1.0, 1.0, 1.0, 0.08):
	set(v):
		empty_color = v
		_push(&"empty_color", v)

func _ready() -> void:
	if material == null:
		material = preload("res://ui/gauges/capacity_pip_material.tres").duplicate()
	resized.connect(_push_size)
	_push_size()
	_push(&"filled", 1.0 if filled else 0.0)
	_push(&"highlight", 1.0 if highlighted else 0.0)
	_push(&"fill_color", fill_color)
	_push(&"empty_color", empty_color)

func _push_size() -> void:
	_push(&"size", size)

func _push(param: StringName, value: Variant) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(param, value)
