extends PoolStat
class_name GrowablePoolStat

signal leveled_up

@export var level: int = -1:
	set(v):
		if v == -1:
			if level == -1:
				v = 1
			else:
				return
		level = v
		notify_property_list_changed()

#func _init() -> void:
	#print('INIT GROWABLE POOL STAT: %s | min: %s | max: %s' % [name, _min.value if _min else 'N/A', _max.value if _max else 'N/A'])


func grow() -> void:
	pass

func set_value(new_value) -> void:
	print('[%s]: setting growable pool stat value from %s to %s' % [name, _value, new_value])
	
	if not _max or not _min:
		print('[%s]: Skipping `set_value`: No _max or _min' % name)
		return
	
	# Don't act if the ranges are fucked
	if _max._value < _min._value:
		print('[%s]: Skipping `set_value`: _max < _min' % name)
		return 
		
	if _value == null:
		_value = _min.value
	
	#if _value == null:
		#super(0)
		#print('_value=null -> called super(0) -> _value=%s' % [_value])
		##super(new_value)
		##new_value = _value
	
	while new_value >= _max.value:
		var size = _max.value - _min.value
		var difference = new_value - size
		_perform_grow()
		print('[%s]: setting difference after level up to %s: %s' % [name, level, difference])

		new_value = difference
		#return set_value(difference)
		#print('[%s]: values now: _v: %s | v: %s' % [name, _value, value])
	
	print('[%s]: new_value<_max.value (%s < %s) -> return super()' % [name, new_value, _max.value])
	#if _value == null:
		#_value = 0
	return super(new_value)


func _perform_grow():
	grow()
	level += 1
	notify_value_changed()
	leveled_up.emit()

func _on_max_increased(_max_value, increase_amount) -> void:
	print('growable pool: max increased of %s by %s to %s' % [name, increase_amount, _max_value])
