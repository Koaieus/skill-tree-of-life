extends PoolStat
class_name IntPoolStat

@export var current_value: int:
	get():
		return _value

@export var max: IntStat = IntStat.new(0):
	set(v):
		max = v
		_max = max
		set_default_value(default_value)

@export var min: IntStat = IntStat.new(0):
	set(v):
		min = v
		_min = min
		set_default_value(default_value)

@export var default_value: int = -1:
	set(v):
		default_value = v
		set_default_value(default_value)
