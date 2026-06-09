@tool
class_name PoolStat
extends ScalarStat

## A pool stat — current value bounded by a modifier-computed cap.
##
## `get_value()` / `.value` returns the computed cap (via the inherited Stat
## modifier pipeline). `.current` is the ephemeral game state. Modifiers
## always target the cap; game systems read/write `.current` directly.
##
## heal_on_max_increase: whenever the cap rises, current follows by the same
## delta. Handled by overriding add/remove_modifier and the derived-modifier
## change hook — no persistent _previous_max tracking required.

signal depleted
signal replenished
signal current_changed(new_current: Variant)

@export var current: float = 0.0


func set_current(v: float) -> void:
	var cap: float = float(get_value())
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
	set_current(float(get_value()))


## Grow the pool's cap by the definition's growth formula.
## Bumps base_value so external modifiers continue to layer atop.
## Returns the delta applied (0 if formula is a no-op or unconfigured).
func grow() -> int:
	if definition == null or not (definition is PoolStatDef):
		return 0
	var def := definition as PoolStatDef
	var old_max := int(get_value())
	var new_max := roundi(float(old_max) * def.growth_factor + float(def.growth_flat))
	var delta := new_max - old_max
	if delta == 0:
		return 0
	base_value += float(delta)
	return delta


# --- Modifier overrides (maintain current ≤ cap on every cap change) -------

func add_modifier(m: StatModifierDef) -> void:
	var old_max := float(get_value())
	super(m)
	_apply_max_change(old_max)


func remove_modifier(m: StatModifierDef) -> void:
	var old_max := float(get_value())
	super(m)
	_apply_max_change(old_max)


func _on_dependent_modifier_changed() -> void:
	var old_max := float(get_value())
	super()
	_apply_max_change(old_max)


func _apply_max_change(old_max: float) -> void:
	var new_max := float(get_value())
	if is_equal_approx(new_max, old_max):
		return
	if current > new_max:
		set_current(new_max)
	elif (definition is PoolStatDef) and (definition as PoolStatDef).heal_on_max_increase:
		set_current(current + (new_max - old_max))


func _min_value() -> int:
	if definition is PoolStatDef:
		return (definition as PoolStatDef).min_value
	return 0
