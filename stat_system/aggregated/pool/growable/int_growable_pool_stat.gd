extends GrowablePoolStat
class_name IntGrowablePoolStat

#@export var current_value: int:
	#get():
		#return _value
		
@export var max: IntStat = IntStat.new(0):
	get(): return max
	set(v):
		max = v
		_max = max

@export var min: IntStat = IntStat.new(0):
	get(): return min
	set(v):
		min = v
		_min = min

@export var default_value: int = 0:
	set(v):
		default_value = v
		set_default_value(default_value)
