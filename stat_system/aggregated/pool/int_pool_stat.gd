extends PoolStat
class_name IntPoolStat

@export var current_value: int:
	get():
		return _value

@export var max: IntStat = IntStat.new(0):
	set(_max_value):
		max = _max_value
		_max = max
		set_default_value(default_value)

@export var min: IntStat = IntStat.new(0):
	set(_min_value):
		min = _min_value
		_min = min
		set_default_value(default_value)

@export var default_value: int = -1:
	set(_default_value):
		default_value = _default_value
		set_default_value(default_value)
