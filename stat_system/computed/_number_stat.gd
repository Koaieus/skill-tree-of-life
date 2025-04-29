extends ComputedStat
class_name NumberStat

signal increased(value: Variant, amount: Variant)
signal decreased(value: Variant, amount: Variant)

var _multiplier: float = 1.0

var multiplier: float:
	get:
		return _multiplier

func compute() -> void:
	var previous = _value
	
	# Reset multiplier (will receive all INCREASE/DECREASE operation values)
	_multiplier = 1.0
	 # Run inherited compute function, which may or may not modify `_multiplier`
	super()
	# Apply multiplier (once)
	apply_multiplier()

	if previous == null:
		return
	
	var amount = _value - previous

	if amount > 0:
		increased.emit(value, amount)
	elif amount < 0:
		decreased.emit(value, amount)

func apply_multiplier() -> void:
	value *= _multiplier
	
