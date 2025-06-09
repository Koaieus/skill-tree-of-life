extends PoolStat
class_name GrowablePoolStat

signal leveled_up

@export var level: int = 1

func grow() -> void:
	pass

func set_value(new_value) -> void:
	print('setting growable pool stat %s value from %s to %s' % [name(), _value, new_value])
	
	# Don't act if the ranges are fucked
	if _max.value <= _min.value:
		return 
		
	if _value == null:
		super(0)
		print('_value=null -> called super(0) -> _value=%s' % [_value])
		#super(new_value)
		#new_value = _value
	
	if new_value < _max.value:
		print('new_value<_max.value (%s < %s) -> return super()' % [new_value, _max.value])
		return super(new_value)

	var difference = new_value - _max.value
	_perform_grow()
	print('setting difference after level up to %s: %s' % [level, difference])
	set_value(difference)

func _perform_grow():
	grow()
	level += 1
	notify_value_changed()
	leveled_up.emit()

func _on_max_increased(_max_value, increase_amount) -> void:
	print('growable pool: max increased of %s by %s to %s' % [name(), increase_amount, _max_value])
