@tool
class_name CompositeBarGauge
extends ColorRect
## Proportional multi-bucket bar — the Skill Points composition bar
## (to-spend / wounded / staked / allocated). Distinct contract from
## PoolGauge: four independent fractions instead of one current/max.
## Bucket 1 ("wounded") pulses per the design's woundPulse keyframe.

@export var to_spend: float = 1.0:
	set(v):
		to_spend = v
		_push_fractions()

@export var wounded: float = 2.0:
	set(v):
		wounded = v
		_push_fractions()

@export var staked: float = 1.0:
	set(v):
		staked = v
		_push_fractions()

@export var allocated: float = 6.0:
	set(v):
		allocated = v
		_push_fractions()

@export var color_to_spend: Color = Color(0.2606, 0.6387, 0.9922, 1.0):
	set(v):
		color_to_spend = v
		_push(&"color_0", v)

@export var color_wounded: Color = Color(0.8725, 0.2322, 0.2404, 1.0):
	set(v):
		color_wounded = v
		_push(&"color_1", v)

@export var color_staked: Color = Color(0.9084, 0.6684, 0.3042, 1.0):
	set(v):
		color_staked = v
		_push(&"color_2", v)

@export var color_allocated: Color = Color(0.588, 0.647, 0.784, 0.30):
	set(v):
		color_allocated = v
		_push(&"color_3", v)

@export_range(0.0, 20.0, 0.5) var corner_radius: float = 5.0:
	set(v):
		corner_radius = v
		_push(&"corner_radius", v)

@export_range(0.0, 8.0, 0.05) var pulse_speed: float = 2.4:
	set(v):
		pulse_speed = v
		_push(&"pulse_speed", v)

func _ready() -> void:
	if material == null:
		material = preload("res://ui/gauges/composite_bar_gauge_material.tres").duplicate()
	resized.connect(_push_size)
	_push_size()
	_push_fractions()
	_push(&"color_0", color_to_spend)
	_push(&"color_1", color_wounded)
	_push(&"color_2", color_staked)
	_push(&"color_3", color_allocated)
	_push(&"corner_radius", corner_radius)
	_push(&"pulse_speed", pulse_speed)

func _push_size() -> void:
	_push(&"size", size)

## Sets all four buckets in one call (the usual binding path from a
## SkillPointStat) rather than firing four separate setters.
func set_buckets(p_to_spend: float, p_wounded: float, p_staked: float, p_allocated: float) -> void:
	to_spend = p_to_spend
	wounded = p_wounded
	staked = p_staked
	allocated = p_allocated

func _push_fractions() -> void:
	var total := to_spend + wounded + staked + allocated
	if total <= 0.0:
		_push(&"fractions", Vector4(0.0, 0.0, 0.0, 0.0))
		return
	_push(&"fractions", Vector4(to_spend / total, wounded / total, staked / total, allocated / total))

func _push(param: StringName, value: Variant) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(param, value)
