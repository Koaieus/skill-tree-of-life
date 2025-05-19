extends AggregatedStat
class_name PoolStat

signal depleted()
signal replenished()
signal increased(value, amount)
signal decreased(value, amount)


var _max: NumberStat
var _min: NumberStat
@export var is_infinite: BoolStat

func display_value():
	return "%s/%s" % [value, _max.value]

func _on_max_increased(_max_value, increase_amount) -> void:
	_value += increase_amount
	print('max increased of %s by %s' % [resource_name, increase_amount])

func _on_max_decreased(_max_value, decrease_amount) -> void:
	_value = _value

func _on_min_increased(_max_value, increase_amount) -> void:
	_value = _value

func _on_min_decreased(_max_value, decrease_amount) -> void:
	_value = _value
	


func initialize() -> void:
	if base_value == -1:
		base_value = _max.value
	
	_value = base_value
	
	StatUtils.connect_if_not_connected(_max.increased, _on_max_increased)
	StatUtils.connect_if_not_connected(_max.decreased, _on_max_decreased)
	StatUtils.connect_if_not_connected(_min.increased, _on_min_increased)
	StatUtils.connect_if_not_connected(_min.decreased, _on_min_decreased)

	#SignalUtils.connect_if_not_connected(_max.increased, _on_max_increased)
	#SignalUtils.connect_if_not_connected(_max.decreased, _on_max_decreased)
	# SignalUtils.connect_if_not_connected(_min.value_changed, update_value)

func set_default_value(_default_value) -> void:
	base_value = _default_value

	if _max == null or _min == null:
		return
	
	initialize()

func set_value(new_value) -> void:
	print('%s: set_value(%s -> %s) @ %s' % [name(), value, new_value, resource_name])

	if is_infinite != null and is_infinite.value:
		return
	
	var previous = _value
	new_value = clamp(new_value, _min.value, _max.value)
	super(new_value)

	# Check if we need to emit a signal related to change in value
	if previous == null:
		return
	var amount = new_value - previous

	if amount > 0:
		increased.emit(new_value, amount)
	elif amount < 0:
		decreased.emit(new_value, amount)
	else:
		return

	if is_empty():
		depleted.emit()
	elif is_full():
		replenished.emit()


func decrease(to_decrease) -> void:
	_value -= to_decrease

func increase(to_increase) -> void:
	_value += to_increase

func replenish() -> void:
	_value = _max.value

func deplete() -> void:
	_value = _min.value


func is_full() -> bool:
	return _max.value == _value

func is_empty() -> bool:
	return _min.value == _value
