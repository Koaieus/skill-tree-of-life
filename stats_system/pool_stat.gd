@tool
class_name PoolStat
extends Stat

## A pool stat — current value bounded by a cap. The cap lives in a sibling
## Stat (`max_stat`, whose own StatDef sits in the registry), so modifiers
## targeting "max health" route through the normal stat_id pipeline rather
## than a sub-stat syntax. See docs/design/stat_system.md.
##
## Named `max_stat` (not `max`) to avoid shadowing GDScript's built-in `max()`.

signal depleted
signal replenished
signal current_changed(new_current: Variant)

@export var current: float = 0.0
@export var max_stat: ScalarStat:
	set(value):
		if max_stat == value:
			return
		if max_stat != null and max_stat.value_changed.is_connected(_on_max_changed):
			max_stat.value_changed.disconnect(_on_max_changed)
		max_stat = value
		if max_stat != null:
			max_stat.value_changed.connect(_on_max_changed)
			_previous_max = float(max_stat.get_value())

## Shorthand for `max_stat.get_value()`. Null if `max_stat` is unset.
var max_value: Variant:
	get: return max_stat.get_value() if max_stat != null else null

var _previous_max: float = 0.0


## A pool's `get_value()` returns its current value. Query the cap via
## `max_value` (or `max_stat.get_value()`).
func get_value() -> Variant:
	return _coerce(current)


func set_current(v: float) -> void:
	var cap: float = float(max_stat.get_value()) if max_stat != null else INF
	var floor_v: float = float(_min_value())
	var clamped: float = clamp(v, floor_v, cap)
	if is_equal_approx(clamped, current):
		return
	var was_below_cap := current < cap
	current = clamped
	current_changed.emit(_coerce(current))
	value_changed.emit()
	if current <= floor_v:
		depleted.emit()
	elif was_below_cap and current >= cap:
		replenished.emit()


func deplete(amount: float) -> void:
	set_current(current - amount)


func replenish(amount: float) -> void:
	set_current(current + amount)


func restore_to_full() -> void:
	if max_stat != null:
		set_current(float(max_stat.get_value()))


func _min_value() -> int:
	if definition is PoolStatDef:
		return (definition as PoolStatDef).min_value
	return 0


func _on_max_changed() -> void:
	if max_stat == null:
		return
	var new_max := float(max_stat.get_value())
	if current > new_max:
		set_current(new_max)
	elif (definition is PoolStatDef) and (definition as PoolStatDef).heal_on_max_increase:
		set_current(current + (new_max - _previous_max))
	_previous_max = new_max
