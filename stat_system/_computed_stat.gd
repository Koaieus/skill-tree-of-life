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
	# Start with base value
	var computed = base_value
		# Sort the modifiers
	stat_modifiers.sort_custom(sort_modifiers_by_application_order)
		# Apply each modifier
	for stat_modifier in stat_modifiers:
		computed = stat_modifier.apply(computed, self)
	# Save result and emit signal
	_value = computed
	value_changed.emit()


#region Stat Modifiers
var stat_modifiers: Array[StatModifier] = []

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
