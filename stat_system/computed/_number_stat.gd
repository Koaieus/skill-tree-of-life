extends ComputedStat
class_name NumberStat

signal increased(value: Variant, amount: Variant)
signal decreased(value: Variant, amount: Variant)

var _multiplier: float = 1.0

var multiplier: float:
	get:
		return _multiplier

func compute() -> void:
	print('>> Computing (number)stats!')
	# Reset multiplier (will receive all INCREASE/DECREASE operation values)
	_multiplier = 1.0
	# Start with base value
	var computed = _apply_modifiers(base_value)
	# Call customizable hook
	computed = _on_after_modifier_application(computed)
	# Save result and emit signal
	var previous = _value
	_value = computed

	if previous == null or _value == null:
		return
	
	var amount = _value - previous
	value_changed.emit()
	if amount > 0:
		increased.emit(value, amount)
	elif amount < 0:
		decreased.emit(value, amount)

func _on_after_modifier_application(v):
	# Apply multiplier (once)
	if v != null:
		v = apply_multiplier(v)
	return v

func apply_multiplier(v):
	print("applying a mult of %s" % _multiplier)
	return v * _multiplier
	
