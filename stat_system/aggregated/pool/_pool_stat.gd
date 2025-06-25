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
	print('max increased of %s by %s' % [name, increase_amount])

func _on_max_decreased(_max_value, decrease_amount) -> void:
	_value = _value

func _on_min_increased(_max_value, increase_amount) -> void:
	_value = _value

func _on_min_decreased(_max_value, decrease_amount) -> void:
	_value = _value
	


func initialize() -> void:
	DeferOnce.defer_once(_initialize)
	
func _initialize() -> void:
	if base_value == -1:
		base_value = _max.value
	
	_value = base_value
	print('[%s] initialized to: %s' % [name, _value])
	StatUtils.connect_if_not_connected(_max.increased, _on_max_increased)
	StatUtils.connect_if_not_connected(_max.decreased, _on_max_decreased)
	#StatUtils.connect_if_not_connected(_min.increased, _on_min_increased)
	#StatUtils.connect_if_not_connected(_min.decreased, _on_min_decreased)

func set_default_value(_default_value) -> void:
	base_value = _default_value

	if _max and _min:
		initialize()
		

func set_value(new_value) -> void:
	print('%s: set_value(%s -> %s)' % [name, value, new_value])

	if is_infinite != null and is_infinite.value:
		return
	
	var previous = _value

	if previous != null:
		new_value = _clamp_value(new_value)
		super(new_value)
		_emit_difference(previous, new_value)
		_emit_extremities()
	else:
		print('[%s]: setting new value (previous was null) to %s' % [name, new_value])
		super(new_value)

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
	
func _clamp_value(v):
	var clamped = clamp(v, _min.value, _max.value)
	print(
		'clamped value %s to %s (min: %s, max: %s)' % [v, clamped, _min.value if _min else 'N/A', _max.value if _max else 'N/A']
	)
	return clamped


func _emit_difference(old_value, new_value) -> void:
	var amount = new_value - old_value
	if amount > 0:
		increased.emit(new_value, amount)
	elif amount < 0:
		decreased.emit(new_value, amount)

## Emits `replenished` (if full) or `depleted` (if empty)
func _emit_extremities() -> void:	
	if is_empty():
		depleted.emit()
	elif is_full():
		replenished.emit()
