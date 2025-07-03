extends ComputedStat
class_name NumberStat

signal increased(value: Variant, amount: Variant)
signal decreased(value: Variant, amount: Variant)

var _multiplier: float = 1.0


func _compute() -> void:
	#if not StatMetaDataRepository.has_method("get_metadata"):
		#return
	#if base_value == null:
		#return
	print('[NumberStat: %s]: Computing...' % [name])
	# Reset multiplier (will receive all INCREASE/DECREASE operation values)
	_multiplier = 1.0
	# Start with base value
	#print_debug('COMPUTING %s FROM BASE VALUE %s' % [name, base_value])
	var computed = _apply_modifiers(base_value)
	# Call customizable hook
	#print('before `_on_after_modifier_application`: %s' % computed)
	computed = _on_after_modifier_application(computed)
	#print('after `_on_after_modifier_application`: %s' % computed)
	# Save result and emit signal
	var previous = _value
	_value = computed

	#print('> prev: %s\tcomputed: %s' % [previous, computed])
	if previous == null or _value == null:
		return
	
	var amount = _value - previous
	#print('> change amount: %s' % [amount])

	if amount:
		notify_value_changed()
	if amount > 0:
		increased.emit(_value, amount)
	elif amount < 0:
		decreased.emit(_value, amount)

func _on_after_modifier_application(v):
	# Apply multiplier (once)
	if v != null:
		v = apply_multiplier(v)
	return v

func apply_multiplier(v):
	print("applying a mult of %s" % _multiplier)
	return v * _multiplier
	
