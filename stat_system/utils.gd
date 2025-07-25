extends Object
class_name StatUtils


#region Signal Utils

static func connect_if_not_connected(sig: Signal, callable: Callable) -> void:
	if not sig.is_connected(callable):
		#print('connecting %s -> %s' % [sig, callable])
		sig.connect(callable)

#endregion

const PRINT_ERROR: bool = false

#region Stat Utils

static func bind_stat(target: Object, property: String, stat_key: GDScript, stats_manager: StatsManager) -> void:
	#print('[BIND]: Binding %s of %s to %s [manager: %s]' % [property, target, stat_key, stats_manager])

	if target == null or property == "":
		if PRINT_ERROR:
			push_error("Target has not been configured properly.")
		return

	if stat_key == null or stats_manager == null:
		if PRINT_ERROR:
			push_error("Stat has not been configured properly.")
		return

	var _stat: Stat = stats_manager.get_stat(stat_key)
	var target_value = target.get(property)

	if target_value != null and target_value is not Object:
		if PRINT_ERROR:
			push_error("Couldn't bind an object to a primitive type, did you meant to bind the value instead ?") 
		return

	if target_value == _stat:
		return
	
	print('[BIND %s]: Setting %s of %s to %s' % [_stat.name, property, target, _stat])
	target.set(property, _stat)


static func unbind_stat(target: Object, property: String) -> void:
	target.set(property, null)


static func bind_stat_value(target: Object, property: String, stat_key: GDScript, stats_manager: StatsManager):
	if target == null or property == "":
		if PRINT_ERROR:
			push_error("Target has not been configured properly.")
		return null
	
	if stat_key == null or stats_manager == null:
		if PRINT_ERROR:
			push_error("Stat has not been configured properly.")
		return null
	
	var target_value = target.get(property)
	if target_value != null and target_value is Object:
		if PRINT_ERROR:
			push_error("Couldn't bind a primitive type to an object, did you meant to bind the stat instead ?")
		return null
			
	var _stat: Stat = stats_manager.get_stat(stat_key)
	assert(_stat != null)

	var _on_value_changed: Callable = \
		func _on_value_changed() -> void: 
			target.set(property, _stat.value)

	_stat.value_changed.connect(_on_value_changed)
	_on_value_changed.call()
	return _on_value_changed


static func unbind_stat_value(target: Object, property: String, _on_value_changed: Callable) -> void:
	if _on_value_changed == null:
		return

	var _stat: Stat = target.get(property) 

	if _stat == null:
		return push_warning("Can't unbind null _stat.")
	
	_stat.value_changed.disconnect(_on_value_changed)
#endregion
