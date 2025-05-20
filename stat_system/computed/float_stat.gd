extends NumberStat
class_name FloatStat
## A computed Float stat comprised of a base value + modifiers

#signal increased(value: float, amount: float)
#signal decreased(value: float, amount: float)

@export var default_value: float = .0:
	set(_default_value):
		default_value = _default_value
		base_value = default_value
		_value = default_value

@export var current_value: float:
	get():
		return _value
