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
## An explicit [method replenish] call, carrying the amount ASKED FOR — the one
## thing `current_changed` can't tell you, since a pool at (or crossing) its cap
## swallows the difference. Deliberately not emitted for `restore_to_full` or a
## direct `set_current`: this is the "you gained N" fact a UI wants to announce,
## not a value-changed notification. See [FloaterDirector]'s XP toast.
signal replenished_by(amount: float)

@export var current: float = 0.0


var pool_definition: PoolStatDef:
	get(): return definition as PoolStatDef

func _init() -> void:
	super()
	if Engine.is_editor_hint():
		current_changed.connect(func(_v): notify_property_list_changed())


func _computed_display() -> String:
	return "%s / %s" % [str(_coerce(current)), str(get_value())]


## The ephemeral half of a pool, exposed as a formula accessor (`current`
## reads `.current`, the cap [method get_value] still read via `&""` — see
## [method Stat.read_accessor]). Composes through [method Stat.accessors].
## The lambda parameter is typed `PoolStat` so a typo like `s.currtent` fails
## at parse time — the silent-wrong-value failure mode this feature exists to
## prevent (#333, Decision 5).
func accessors() -> Dictionary[StringName, Callable]:
	var d := super.accessors()
	d.merge({&"current": func(s: PoolStat): return s.current})
	return d


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
			var companion_id := pool_definition.resolved_per_turn_stat_id()
			var companion := board.get_stat(companion_id)
			if companion == null:
				push_warning("PoolStat '%s' is ADD per-turn but has no '%s' companion stat" % [definition.id, companion_id])
				return
			var amount := float(companion.get_value())
			if amount > 0.0:
				replenish(amount)
		PoolStatDef.PerTurnMode.CUSTOM:
			_custom_turn_upkeep(board)


## CUSTOM-mode hook. Base no-op; stat subclasses with bespoke turn-start
## behaviour override this. Lives on the stat (not the def) because it
## manipulates the stat's own extra state — see SkillPointStat (wound-heal).
@warning_ignore("shadowed_variable_base_class")
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
	_emit_value_changed()
	if current <= floor_v:
		depleted.emit()
	elif was_below_cap and current >= cap:
		if pool_definition != null and cap > 0:
			pool_definition.on_pool_filled(self, excess)
		replenished.emit()


## Spendable-this-turn budget. On a plain pool this is just `current`; the
## [SurplusPoolStat] subclass adds its out-of-cap surplus bin on top. Gates and
## budgets should read this (not `current`) so a transient surplus is honoured
## polymorphically without the caller knowing which subclass it holds.
func available() -> int:
	return roundi(current)


func deplete(amount: float) -> void:
	set_current(current - amount)


func replenish(amount: float) -> void:
	set_current(current + amount)
	if amount > 0.0:
		# AFTER set_current, so a listener that re-reads the pool sees the result
		# (and any level-up the fill cascaded into) rather than the old state.
		replenished_by.emit(amount)


func restore_to_full() -> void:
	set_current(float(get_value()))


## Move `base_value` **through** the cap-change behaviour — grant the delta on a
## rise (via the def's [method PoolStatDef.on_max_increased]), clamp `current` on
## a fall. This is the ratcheted one of the two doors onto a pool's cap:
##
##   pool.set_base_ratcheted(v)   # cap change behaves like a modifier's would
##   pool.base_value = v          # RAW — deliberately skips all of the above
##
## The raw door is not a bug and must not be welded shut: [method
## SkillPointStat.claim] *is* that bypass (it grows max without handing over a
## spendable point — the whole difference from `grant`, and AllocationSystem
## calls it on every allocation), and [GrowablePoolStatDef]'s level-up growth
## relies on it for the same reason.
##
## Reach for the raw write only when you can name why the cap should move
## without `current` following, and leave that reason in a comment. Otherwise
## use this. See docs/domain/stat-knobs-and-bins.md §3 and D-31.
func set_base_ratcheted(v: float) -> void:
	var old_max := float(get_value())
	base_value = v
	_apply_max_change(old_max)


# --- Modifier overrides (maintain current ≤ cap on every cap change) -------

func add_modifier(m: StatModifier, board: StatBoard = null) -> void:
	var old_max := float(get_value())
	super(m, board)
	_apply_max_change(old_max)


func remove_modifier(m: StatModifier, board: StatBoard = null) -> void:
	var old_max := float(get_value())
	super(m, board)
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
