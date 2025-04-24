extends NumberStat
class_name IntStat
## A computed Int stat comprised of a base value + modifiers

#signal increased(value: int, amount: int)
#signal decreased(value: int, amount: int)

@export var default_value: int = 0:
	set(_default_value):
		default_value = _default_value
		base_value = default_value
		_value = default_value
