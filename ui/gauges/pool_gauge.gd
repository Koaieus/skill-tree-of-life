@tool
class_name PoolGauge
extends ColorRect
## Reusable "Arcane Terminal" pool gauge. cell_count == 0 renders a smooth
## continuous bar (Health/Mana/XP); cell_count > 0 renders N skewed
## parallelogram "battery" cells (AP/DP/Move). Every exported value pushes
## to the shader immediately in its setter, so tuning is live (and
## animated — shine, drain-trail) in the Inspector, not just at runtime.

const DRAIN_FADE_TIME := 0.9

@export var current: float = 1.0:
	set(v):
		var old := current
		current = v
		if v < old:
			# Freeze the ghost at the old value, then tween it down to the
			# new one so the loss reads as a fading trail, not a snap.
			drain_from = old
			_animate_drain_to(v)
		else:
			drain_from = v
		_push(&"current", current)

@export var min_value: float = 0.0:
	set(v):
		min_value = v
		_push(&"min_value", v)

@export var max_value: float = 2.0:
	set(v):
		max_value = v
		_push(&"max_value", v)

## Ghost/previous value driving the drain trail. Normally managed
## automatically by the `current` setter; exposed for manual scripting.
@export var drain_from: float = 1.0:
	set(v):
		drain_from = v
		_push(&"drain_from", v)

@export var fill_color: Color = Color(0.7, 0.75, 0.95, 1.0):
	set(v):
		fill_color = v
		_push(&"fill_color", v)

@export var empty_color: Color = Color(1.0, 1.0, 1.0, 0.08):
	set(v):
		empty_color = v
		_push(&"empty_color", v)

@export var glow_color: Color = Color(1.0, 1.0, 1.0, 0.6):
	set(v):
		glow_color = v
		_push(&"glow_color", v)

@export var drain_color: Color = Color(0.9, 0.3, 0.3, 0.5):
	set(v):
		drain_color = v
		_push(&"drain_color", v)

@export_range(0.0, 4.0, 0.05) var shine_speed: float = 0.6:
	set(v):
		shine_speed = v
		_push(&"shine_speed", v)

## 0 = smooth continuous bar. N = N skewed parallelogram cells.
@export_range(0.0, 16.0, 1.0) var cell_count: float = 0.0:
	set(v):
		cell_count = v
		_push(&"cell_count", v)

@export_range(-45.0, 45.0, 0.5) var skew_degrees: float = 0.0:
	set(v):
		skew_degrees = v
		_push(&"skew_degrees", v)

@export_range(0.0, 20.0, 0.5) var corner_radius: float = 4.0:
	set(v):
		corner_radius = v
		_push(&"corner_radius", v)

@export_range(0.0, 12.0, 0.5) var cell_gap: float = 3.0:
	set(v):
		cell_gap = v
		_push(&"cell_gap", v)

var _drain_tween: Tween

func _ready() -> void:
	if material == null:
		material = preload("res://ui/gauges/pool_gauge_material.tres").duplicate()
	resized.connect(_push_size)
	_push_size()
	_push_all()

func _push_size() -> void:
	_push(&"size", size)

func _push_all() -> void:
	_push(&"current", current)
	_push(&"min_value", min_value)
	_push(&"max_value", max_value)
	_push(&"drain_from", drain_from)
	_push(&"fill_color", fill_color)
	_push(&"empty_color", empty_color)
	_push(&"glow_color", glow_color)
	_push(&"drain_color", drain_color)
	_push(&"shine_speed", shine_speed)
	_push(&"cell_count", cell_count)
	_push(&"skew_degrees", skew_degrees)
	_push(&"corner_radius", corner_radius)
	_push(&"cell_gap", cell_gap)

func _animate_drain_to(target: float) -> void:
	if not is_inside_tree():
		drain_from = target
		return
	if _drain_tween:
		_drain_tween.kill()
	_drain_tween = create_tween()
	_drain_tween.tween_property(self, ^"drain_from", target, DRAIN_FADE_TIME)

func _push(param: StringName, value: Variant) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(param, value)
