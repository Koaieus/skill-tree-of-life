extends NumberStat
class_name IntStat
## A computed Int stat comprised of a default value + modifiers

#signal increased(value: int, amount: int)
#signal decreased(value: int, amount: int)

@export var default_value: int = 0:
	set(_default_value):
		default_value = _default_value
		base_value = default_value
		_value = default_value

func apply_multiplier(v):
	var new_v := roundi(v * _multiplier)
	#print("applying a mult of %s then rounding (to: %s)" % [_multiplier, new_v])
	return new_v
