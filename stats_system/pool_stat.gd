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
	_set_current_with_cap(v, float(get_value()))


## [method set_current] for a caller that ALREADY knows the cap.
##
## Exists for #470: `set_current` re-derived the cap through the whole modifier
## pipeline, and on the CON fan-out path that was the fourth full evaluation of
## the same number in one call — `_apply_max_change` had just computed it two
## frames up and dropped it. Measured 1.18us/node of an 8.4us/node fan-out.
## Pass the cap when you have it; call [method set_current] when you don't.
func _set_current_with_cap(v: float, cap: float) -> void:
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
	var cap := float(get_value())
	_set_current_with_cap(cap, cap)


## Guard for [method _set_base_minted] — see there. Never set it anywhere else.
var _bypass_cap_policy: bool = false


## [b]The cap-change policy runs on a plain `pool.base_value = v`[/b] (#555).
##
## [Stat] declares `base_value` with `set = _set_base_value` precisely so this
## override is reachable, which is what makes the ordinary-looking assignment the
## CORRECT door. Before #555 it was the silent-bypass one and `set_base_ratcheted`
## was the correct one — an inverted default that shipped #346 (every allocated
## node reading at 0.1 fill, because the node-HP sync used the plain write).
##
## `old_max` must be read BEFORE the assignment, so it cannot be hoisted out.
func _set_base_value(v: float) -> void:
	if _bypass_cap_policy or v == base_value:
		super(v)
		return
	var old_max := float(get_value())
	super(v)
	_apply_max_change(old_max)


## [b]The mint door[/b] — move the cap WITHOUT the def's cap-change policy.
##
## Private, and deliberately so: there are exactly three mint sites in the whole
## project ([method SkillPointStat.claim], [method SkillPointStat.grant],
## [method GrowablePoolStatDef.on_pool_filled]'s growth), all inside
## `stats_system/`, and NO gameplay code outside it has any business here. A
## mint is "this pool's own base is game state it grows itself", not "the cap
## followed something else" — the latter is a plain assignment.
##
## Board init and [method StatBoard.clone_live] use it too: seeding or copying a
## base is not a cap CHANGE and must not move `current`.
func _set_base_minted(v: float) -> void:
	_bypass_cap_policy = true
	base_value = v
	_bypass_cap_policy = false


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


## Run the def's cap-change policy, then enforce the clamp invariant.
##
## [b]The clamp is not a mode.[/b] Whatever the policy did, `current` ends up
## bounded by the cap. Budget that legitimately exceeds the maximum lives in a
## separate bin outside it ([SurplusPoolStat.surplus]) — which nothing here
## touches, on a rise or a fall, by that class's contract.
func _apply_max_change(old_max: float) -> void:
	var new_max := float(get_value())
	if is_equal_approx(new_max, old_max):
		return
	var d := pool_definition
	if d != null:
		var follows := (
			d.on_cap_rise == PoolStatDef.CapRise.FOLLOW if new_max > old_max
			else d.on_cap_fall == PoolStatDef.CapFall.FOLLOW
		)
		if follows:
			_follow_cap_delta(new_max - old_max, new_max)
	# The invariant, always, whatever the policy chose.
	if current > new_max:
		_set_current_with_cap(new_max, new_max)


## Move `current` by a cap delta — [b]the D-21 ratchet[/b], and the one place to
## change it. Signed: positive on a FOLLOW rise, negative on a FOLLOW fall.
##
## On `health` the rise direction is knowingly exploitable: allocating a big-CON
## node raises the cap and hands you the delta as HP immediately, so a player can
## cycle territory to heal. D-21 accepts that — engineering your graph to move
## your numbers is legitimate play in a game where the skill graph *is* the
## mechanics; the bar is "doesn't make it too easy", not "loophole-free". The
## exploit is bounded because DP is not free.
##
## D-26 requires this to stay a single named method, never inlined into an
## allocation path, so that when the ratchet is revisited the seam is findable.
## It replaces `StandardPoolStatDef.grant_max_increase_delta` (#555); the toggle
## that used to be `heal_on_max_increase` is now `on_cap_rise` on the def.
func _follow_cap_delta(delta: float, cap: float) -> void:
	_set_current_with_cap(current + delta, cap)


func _min_value() -> int:
	if definition is PoolStatDef:
		return pool_definition.min_value
	return 0
