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

## The pool's fill, ALWAYS in absolute units — read it, write it, serialize it
## exactly as before. What changed in #660 is what sits behind it: this is a
## property over [member _state], whose MEANING is the pool's representation
## policy (see [method stores_missing]). A missing-storage pool derives this on
## every read from the live cap, which is what lets that cap move with no
## per-node notification at all.
##
## The setter is deliberately RAW — no clamp, no signal — because that is what
## the plain `@export var` it replaces was. `.tres` deserialization writes
## `current` BEFORE `definition` and `base_value` (the file is alphabetical), so
## a clamping setter here would pin every authored pool to a cap of 0.
## Clamping and crossings live in [method set_current], as they always have.
@export var current: float = 0.0:
	get = _get_current, set = _set_current_field

## The single float of health state this pool actually stores.
##
## [b]One field, two meanings, chosen by authored policy[/b] — never two fields
## (house rule: no parallel mirrors of logic). Stored-current pools keep the
## absolute fill here; missing-storage pools keep DAMAGE TAKEN. Nothing outside
## this class reads it: [member current] is the one accessor, in both
## representations.
var _state: float = 0.0

## Live source for this pool's cap BASE, replacing the stored [member base_value]
## when set (#660). Installed by [method NodeCombat.get_max_hp]'s pool accessor
## on a node's `node_health` pool, where the base IS the owner's `node_health`
## baseline and pushing it per-node was the CON fan-out this issue deletes.
##
## Not exported, so `duplicate()` never carries one world's provider into
## another's clone — a shadow installs its own, pointed at its own owner.
var base_provider: Callable = Callable()


## True iff this pool stores DAMAGE TAKEN rather than an absolute fill.
##
## The discriminator is the def's own policy, not a separate switch: a pool that
## FOLLOWs its cap in both directions is, by definition, one whose `missing` is
## the invariant — so storing `missing` and deriving `current = max(floor, cap −
## missing)` IS that policy, exactly, with no cap-change work to do. A pool that
## CLAMPs on the way down has a fill that is genuinely independent of its cap and
## must store it.
##
## Consequences that fall out rather than being implemented (#660):
## - the cap may move with no notification and `current` stays correct;
## - a dip-and-restore round trip heals nothing (path independence);
## - a cap fall past `missing` floors at [method _min_value] — the sliver — and
##   death stays exclusively inside [method NodeCombat.take_damage].
func stores_missing() -> bool:
	var d := pool_definition
	return (
		d != null
		and d.on_cap_rise == PoolStatDef.CapRise.FOLLOW
		and d.on_cap_fall == PoolStatDef.CapFall.FOLLOW
	)


func _get_current() -> float:
	if stores_missing():
		return maxf(float(_min_value()), float(get_value()) - _state)
	return _state


## Raw write half of [member current] — see its doc for why this does not clamp.
func _set_current_field(v: float) -> void:
	_store_current(v, float(get_value()) if stores_missing() else 0.0)


## [method _set_current_field] for a caller that already knows the cap, so a
## clamp-and-store round trip runs the cap pipeline once instead of twice.
func _store_current(v: float, cap: float) -> void:
	if stores_missing():
		_state = maxf(0.0, cap - v)
	else:
		_state = v


## Transfer this pool's state to [param dst] in its STORED representation.
##
## [method StatBoard.clone_live] copies bins by hand after the base, so at the
## moment it transfers state the clone's cap is still bare `base_value` — an
## absolute `dst.current = src.current` would be re-encoded against the wrong
## cap on a missing-storage pool. Both sides hold the same def and therefore the
## same policy, so copying the raw field is exact and order-independent.
func copy_state_from(src: PoolStat) -> void:
	if src == null:
		return
	_state = src._state


var pool_definition: PoolStatDef:
	get(): return definition as PoolStatDef

func _init() -> void:
	super()
	if Engine.is_editor_hint():
		current_changed.connect(func(_v): notify_property_list_changed())


## The cap. [member base_provider] wins over the stored [member base_value] when
## one is installed, and such a read deliberately SKIPS #470's memo: a provided
## base moves with no signal to dirty it, so caching it is the one thing that
## would make lazy defer a VALUE rather than a signal. The fold itself is the
## identical [method ModifierBins.compute_single] over the identical bins in the
## identical insertion order — #463's stable-order obligation is untouched.
func get_value() -> Variant:
	if base_provider.is_valid():
		return _coerce(ModifierBins.compute_single(float(base_provider.call()), bins))
	return super()


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


## Adds the ephemeral half — [member current] — to [method Stat.to_dict].
## The CAP is not written: it is [method get_value], which is derived and
## recomputed by the receiver from base + modifiers.
func to_dict() -> Dictionary:
	var d := super()
	d["current"] = current
	return d


## [member current] is restored LAST, after `super()` has rebuilt base and the
## modifier list — so it lands against the payload's cap, not the receiver's
## stale one.
##
## Written RAW rather than through [method set_current], deliberately: the
## setter's crossings fire the def's [method PoolStatDef.on_pool_filled] (an
## `xp` pool restored at full would level the entity up on arrival) and
## [signal depleted] (a `health` pool restored at 0 would kill it). A snapshot
## transports a state that already happened; it must not re-run its
## consequences. The notifications a UI needs are emitted by hand just below —
## same split [method StatBoard.clone_live] makes for the same reason.
func read_dict(d: Dictionary, board: StatBoard = null) -> void:
	super(d, board)
	current = float(d.get("current", 0.0))
	current_changed.emit(_coerce(current))
	_emit_value_changed()


## Transporting a cap is not a cap CHANGE — mint it, so the def's rise/fall
## policy does not move the `current` [method read_dict] restores verbatim one
## line later. The fourth and last mint site, and like the other three it lives
## inside `stats_system/` (see [method _set_base_minted]).
func _read_base(v: float) -> void:
	_set_base_minted(v)


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
	_store_current(clamped, cap)
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
	# A missing-storage pool has NOTHING to do here: FOLLOW in both directions
	# and the clamp invariant are both what `current = max(floor, cap − missing)`
	# already means. This early return is the deleted fan-out, at the seam where
	# the per-node work used to happen (#660).
	if stores_missing():
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
