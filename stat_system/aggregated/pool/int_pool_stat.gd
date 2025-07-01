extends PoolStat
class_name IntPoolStat

@export var current_value: int:
	get():
		return _value

@export var max: IntStat = IntStat.new(0):
	set(v):
		max = v
		_max = max
		set_default_value(default_value)

@export var min: IntStat = IntStat.new(0):
	set(v):
		min = v
		_min = min
		set_default_value(default_value)

@export var default_value: int = -1:
	set(v):
		default_value = v
		set_default_value(default_value)


#func _get_property_list():
	#var list := []
	##if _min is IntStat and _max is IntStat:
	#list.append({
		#name = &"value_slider",
		#type = TYPE_INT,
		#hint = PROPERTY_HINT_RANGE,
		##hint_string = "%s,%s" % [0, 0],
		#hint_string = "%s,%s" % [_min.value, _max.value],
		#usage = PROPERTY_USAGE_EDITOR
	#})
	##else:
		##print_debug('No _min or no _max: %s, %s' % [_min, _max])
	#return list
#
#func _get(property: StringName):
	#if property == &"value_slider":
		#return value
	#return null
#
#func _set(property: StringName, val):
	#if property == &"value_slider":
		#value = val
		#notify_property_list_changed()
		#return true
	#return false
