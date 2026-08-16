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

## Addon-outline colors (melee blade blips, #406 follow-up) — a transparent
## alpha (the default) means "no outline of this kind". Two set at once split
## the shader's outline band and rotate it; see capacity_pip.gdshader.
@export var outline_color_a: Color = Color(0, 0, 0, 0):
	set(v):
		outline_color_a = v
		_push(&"outline_color_a", v)
		_push(&"has_outline_a", 1.0 if v.a > 0.0 else 0.0)

@export var outline_color_b: Color = Color(0, 0, 0, 0):
	set(v):
		outline_color_b = v
		_push(&"outline_color_b", v)
		_push(&"has_outline_b", 1.0 if v.a > 0.0 else 0.0)

## Rectangular border marking a player-applied (temp) upgrade, as opposed to
## one that shipped from procgen — deliberately a plain rect, not another
## shader ring, so it reads as distinct from the diamond fill/outline.
@export var manual_marker: bool = false:
	set(v):
		manual_marker = v
		if _marker_border != null:
			_marker_border.visible = v

@onready var _marker_border: Control = $MarkerBorder

func _ready() -> void:
	if material == null:
		material = preload("res://ui/gauges/capacity_pip_material.tres").duplicate()
	resized.connect(_push_size)
	_push_size()
	_push(&"filled", 1.0 if filled else 0.0)
	_push(&"highlight", 1.0 if highlighted else 0.0)
	_push(&"fill_color", fill_color)
	_push(&"empty_color", empty_color)
	_push(&"outline_color_a", outline_color_a)
	_push(&"has_outline_a", 1.0 if outline_color_a.a > 0.0 else 0.0)
	_push(&"outline_color_b", outline_color_b)
	_push(&"has_outline_b", 1.0 if outline_color_b.a > 0.0 else 0.0)
	_marker_border.visible = manual_marker

func _push_size() -> void:
	_push(&"size", size)

func _push(param: StringName, value: Variant) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(param, value)
