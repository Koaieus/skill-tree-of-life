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
	print('>> Computing stat "%s"' % name)
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
		#if parent:
			#print('[%s] emitting value changed (from parent %s)' % [name, parent.resource_name])
			#parent.stats_changed.emit()

func _apply_modifiers(start_value: Variant):
	if start_value == null:
		return null
	var updated_value = start_value
	# Sort the modifiers
	stat_modifiers.sort_custom(sort_modifiers_by_application_order)
	# Apply each modifier
	for stat_modifier in stat_modifiers:
		var old_value = updated_value
		var script: GDScript = get_script()
		updated_value = stat_modifier.apply(updated_value, self)
		print_debug('%s modified from %s to %s' % [name, old_value, updated_value])
	return updated_value

	
#region Stat Modifiers
@export var stat_modifiers: Array[StatModifier] = []

func add_stat_modifier(stat_modifier: StatModifier) -> void:
	var existing_modifier_idx := stat_modifiers.find(stat_modifier)
	if existing_modifier_idx != -1:
		stat_modifiers[existing_modifier_idx].apply_count += stat_modifier.apply_count
	else:
		stat_modifiers.append(stat_modifier)
		stat_modifier.apply_count_changed.connect(compute)
	compute()

func remove_stat_modifier(stat_modifier: StatModifier) -> void:
	var existing_modifier_idx := stat_modifiers.find(stat_modifier)
	if existing_modifier_idx == -1:
		push_error('Cannot remove StatModifier %s: Not in list of stat modifiers')
		return
	
	var existing_mod: StatModifier = stat_modifiers[existing_modifier_idx]
	assert(
		existing_mod.apply_count >= stat_modifier.apply_count, 
		"Cannot remove %s applications of %s, as apply count is merely %s" % [
			stat_modifier.apply_count, stat_modifier, existing_mod.apply_count
		]
	)
	var new_apply_count = existing_mod.apply_count - stat_modifier.apply_count
	if new_apply_count == 0:
		stat_modifiers.erase(existing_mod)
		existing_mod.apply_count_changed.disconnect(compute)
	compute()

func clear_stat_modifiers() -> void:
	for stat_modifier in stat_modifiers:
		stat_modifier.apply_count_changed.disconnect(compute)

	stat_modifiers.clear()
	compute()
	
func _on_after_modifier_application(value):
	return value
	
func _on_base_value_changed(new_value, old_value):
	compute()

#endregion


#region Constructor
func _init(_base_value = base_value) -> void:
	base_value = _base_value
	#compute()
#endregion


#region Sorting
func sort_modifiers_by_application_order(stat_modifier_a: StatModifier, stat_modifier_b: StatModifier) -> bool:
	return stat_modifier_a.application_order < stat_modifier_b.application_order
#endregion
