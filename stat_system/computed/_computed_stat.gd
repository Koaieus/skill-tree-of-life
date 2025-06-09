extends Stat
class_name ComputedStat
## Base class for stats for which the current value is calculated by
##	adding modifiers to a base value
## Concrete sumclasses can implement stats that handle different data types,
##	such as Int or Float

# Internal value
var _value

# Return (cached) computed value
func get_value():
	return _value

# (Re-)compute the computed value
func compute() -> void:
	print('>> Computing stats!')
	# Save current value as previous
	var previous = _value
	# Start with base value
	var computed = _apply_modifiers(base_value)
	# Call customizable hook
	computed = _on_after_modifier_application(computed)
	# If different: Save result and emit signal
	if _value != computed:
		_value = computed
		notify_value_changed()
		if parent:
			print('[%s] emitting value changed (from parent %s)' % [name(), parent.resource_name])
			parent.stats_changed.emit()

func _apply_modifiers(start_value: Variant):
	var updated_value = start_value
	# Sort the modifiers
	stat_modifiers.sort_custom(sort_modifiers_by_application_order)
	# Apply each modifier
	for stat_modifier in stat_modifiers:
		print()
		var old_value = updated_value
		updated_value = stat_modifier.apply(updated_value, self)
		print_debug('%s modified from %s to %s' % [name(), old_value, updated_value])
	return updated_value

	
#region Stat Modifiers
@export var stat_modifiers: Array[StatModifier] = []

func add_stat_modifier(stat_modifier: StatModifier) -> void:
	stat_modifiers.append(stat_modifier)
	stat_modifier.apply_count_changed.connect(compute)
	compute()

func remove_stat_modifier(stat_modifier: StatModifier) -> void:
	stat_modifiers.erase(stat_modifier)
	stat_modifier.apply_count_changed.disconnect(compute)
	compute()

func clear_stat_modifiers() -> void:
	for stat_modifier in stat_modifiers:
		stat_modifier.apply_count_changed.disconnect(compute)

	stat_modifiers = []
	compute()
	
func _on_after_modifier_application(value):
	return value
	
func _on_base_value_changed(new_value, old_value):
	compute()

#endregion


#region Constructor
func _init(_base_value = base_value) -> void:
	base_value = _base_value
	compute()
#endregion


#region Sorting
func sort_modifiers_by_application_order(stat_modifier_a: StatModifier, stat_modifier_b: StatModifier) -> bool:
	return stat_modifier_a.application_order < stat_modifier_b.application_order
#endregion
