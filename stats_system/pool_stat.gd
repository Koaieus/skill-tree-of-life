@tool
class_name PoolStat
extends ScalarStat

## A pool stat — current value bounded by a modifier-computed cap.
##
## `get_value()` / `.value` returns the computed cap (via the inherited Stat
## modifier pipeline). `.current` is the ephemeral game state. Modifiers
## always target the cap; game systems read/write `.current` directly.
##
## Behaviour on cap-rise (heal-on-max-increase) and on cap-fill (growth) is
## delegated to the def — see PoolStatDef.on_max_increased / on_pool_filled
## and the StandardPoolStatDef / GrowablePoolStatDef subclasses. This class
## stays agnostic to which subclass it holds.

signal depleted
signal replenished
signal current_changed(new_current: Variant)

@export var current: float = 0.0


var pool_definition: PoolStatDef:
	get(): return definition as PoolStatDef

func _init() -> void:
	super()
	if Engine.is_editor_hint():
		current_changed.connect(func(_v): notify_property_list_changed())


func _computed_display() -> String:
	return "%s / %s" % [str(_coerce(current)), str(get_value())]


## Apply this pool's start-of-turn replenishment, per its def's per_turn_mode.
## Called from StatBoard.apply_per_turn_upkeep() for every pool. `board` is
## needed to resolve sibling stats (ADD's companion, CUSTOM's inputs).
func run_turn_upkeep(board: StatBoard) -> void:
	if pool_definition == null:
		return
	match pool_definition.per_turn_mode:
		PoolStatDef.PerTurnMode.REFILL:
			restore_to_full()
		PoolStatDef.PerTurnMode.ADD:
			var companion := board.get_stat(StringName("%s_per_turn" % definition.id))
			if companion == null:
				push_warning("PoolStat '%s' is ADD per-turn but has no '%s_per_turn' companion stat" % [definition.id, definition.id])
				return
			var amount := float(companion.get_value())
			if amount > 0.0:
				replenish(amount)
		PoolStatDef.PerTurnMode.CUSTOM:
			_custom_turn_upkeep(board)


## CUSTOM-mode hook. Base no-op; stat subclasses with bespoke turn-start
## behaviour override this. Lives on the stat (not the def) because it
## manipulates the stat's own extra state — see SkillPointStat (wound-heal).
func _custom_turn_upkeep(_board: StatBoard) -> void:
	pass


func set_current(v: float) -> void:
	var cap: float = float(get_value())
	var floor_v: float = float(_min_value())
	var clamped: float = clamp(v, floor_v, cap)
	if is_equal_approx(clamped, current):
		return
	var was_below_cap := current < cap
	var excess: float = max(0.0, v - cap)
	current = clamped
	current_changed.emit(_coerce(current))
	value_changed.emit()
	if current <= floor_v:
		depleted.emit()
	elif was_below_cap and current >= cap:
		if pool_definition != null and cap > 0:
			pool_definition.on_pool_filled(self, excess)
		replenished.emit()


func deplete(amount: float) -> void:
	set_current(current - amount)


func replenish(amount: float) -> void:
	set_current(current + amount)


func restore_to_full() -> void:
	set_current(float(get_value()))


# --- Modifier overrides (maintain current ≤ cap on every cap change) -------

func add_modifier(m: StatModifier) -> void:
	var old_max := float(get_value())
	super(m)
	_apply_max_change(old_max)


func remove_modifier(m: StatModifier) -> void:
	var old_max := float(get_value())
	super(m)
	_apply_max_change(old_max)


func _on_dependent_modifier_changed(m: StatModifier) -> void:
	var old_max := float(get_value())
	super(m)
	_apply_max_change(old_max)


func _apply_max_change(old_max: float) -> void:
	var new_max := float(get_value())
	if is_equal_approx(new_max, old_max):
		return
	if current > new_max:
		set_current(new_max)
	elif new_max > old_max and pool_definition != null:
		pool_definition.on_max_increased(self, new_max - old_max)


func _min_value() -> int:
	if definition is PoolStatDef:
		return pool_definition.min_value
	return 0
