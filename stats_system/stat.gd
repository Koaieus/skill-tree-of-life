@tool
@abstract
class_name Stat
extends Resource

## Runtime stat. Pairs a StatDef (identity, type, display) with a base value
## and a modifier list. v2 of the stat system; see docs/design/stat_system.md.
##
## Modifier pipeline (PoE-style with a late additive):
##   SET wins outright (highest priority, last-in breaks ties). Otherwise:
##     result = (base + Σ ADD_BASE)
##           × (1 + Σ INCREASE / 100)
##           × Π MULTIPLY
##           + Σ ADD_BONUS
##   INT stats round once, here. See StatModifier for value-scale conventions.

signal value_changed

@export var definition: StatDef:
	set(v):
		definition = v
		_sync_resource_name()
		
## Runtime base value this entity's stat starts at (usually inherited from
## the board .tres; 0.0 initially). [member StatDef.default_value] is a
## separate manufacturing default — used by [method SkillNode.get_local_value]
## when the entity board doesn't carry the stat at all so reads can still
## return a sensible value. They are not coupled: base_value is the
## entity's *own* starting point after init; default_value is the system-wide
## "if absent" floor.
##
## [b]On a [PoolStat], writing this is the RAW door onto the cap[/b]: it emits
## [signal value_changed] but deliberately does NOT run the cap-change behaviour
## ([method PoolStat._apply_max_change] is reachable only from the modifier
## path), so there is no grant on a rise and no clamp of `current` on a fall.
## That bypass is load-bearing — [method SkillPointStat.claim] and
## [GrowablePoolStatDef]'s growth are both defined by it. If you want the
## ratchet, use [method PoolStat.set_base_ratcheted]. See D-31 /
## docs/domain/stat-knobs-and-bins.md §3 — routing this setter through the
## ratchet mints a spendable SP on every allocation.
@export var base_value: float = 0.0:
	set(v):
		if v == base_value:
			return
		base_value = v
		# Computed value moves with base_value; notify subscribers (UI, formula
		# modifiers watching this stat) so reactive paths stay coherent when
		# scripts write base_value directly.
		_emit_value_changed()

var _modifiers: Array[StatModifier] = []

## Per-operation pipeline bins, factored into ModifierBins so multi-source
## reads (e.g. a node-local stat layering on top of an entity-side Stat) can compose
## via bin-sum + one pipeline run. See modifier_bins.gd for the algebra.
##
## ADD_BASE / INCREASE / ADD_BONUS keep a running scalar sum — additions are
## pure float adds; FP drift over many add/remove cycles is negligible (stat
## values are small, INT stats coerce via roundi). MULTIPLY intentionally
## keeps the *list* and walks it on read: a running product would require
## division on remove (FP-drift trap) and a value-of-0 modifier would wedge
## it. The multiplier list is typically tiny (0–2), so the walk is cheap.
##
## SET caches its winner (`bins.winning_set`) so get_value() early-returns
## in O(1) — SET is the only op where composition order matters.
##
## `_last_contrib` remembers what each non-SET, non-MULTIPLY modifier last
## added to its bin. When a modifier's `changed` fires (live value edit or
## formula-source moved), we apply `(new − last)` as a delta, mirroring
## add/remove through one path.
var bins: ModifierBins = ModifierBins.new()
var _last_contrib: Dictionary = {}

## The board this stat lives on — set the first time a caller passes one to
## [method add_modifier] / [method remove_modifier], and remembered for
## reactive recomputation ([method _on_dependent_modifier_changed],
## [method _resync_bins_if_trivial]) that fires later with no board in scope.
## Safe to hold directly (unlike the removed [code]StatModifier._board[/code]):
## a [Stat] instance is never shared across boards — it IS the per-board
## storage — so there is exactly one board to remember, ever (#377).
##
## Mirrored onto [member bins].board (in [method add_modifier] /
## [method remove_modifier], the only writers) so [method ModifierBins.compute]
## (a static function with no Stat in scope) can resolve each SET-winner /
## MULTIPLY modifier against the RIGHT board when composing multiple stats'
## bins — see [method SkillNode.get_local_value], which merges an entity
## Stat's bins with a node Stat's bins in one call. Each source's own board
## travels with it.
var _board: StatBoard = null


## Every `value_changed` emission in this class routes through here so a board
## can coalesce a burst of them (see [method StatBoard.begin_batch]). Outside a
## batch this is exactly `value_changed.emit()`.
##
## Deferring the SIGNAL never defers the VALUE: [method get_value] recomputes
## from the bins on every call, so a read taken mid-batch is already correct.
## Only the notification waits.
func _emit_value_changed() -> void:
	if _board != null and _board.is_batching():
		_board.mark_stat_dirty(self)
		return
	value_changed.emit()


## Shorthand for `get_value()`. Delegates so subclass overrides win — e.g.
## `pool.value` returns the pool's current via PoolStat's override.
var value: Variant:
	get: return get_value()


func _init() -> void:
	if Engine.is_editor_hint():
		value_changed.connect(notify_property_list_changed)


## Returns [code]true[/code] if [param m] is already in this stat's modifier list.
func has_modifier(m: StatModifier) -> bool:
	return m in _modifiers


## Fold the dependency edges of every modifier applied to this stat into a
## `{stat_id: [depends_on_id, ...]}` graph, in place — the live half of
## [method StatBoard.would_cycle]'s graph (#322).
##
## Tell-don't-ask on purpose: `_modifiers` never leaves the Stat, so no caller
## can append an unbound modifier into it (which would sit in the list without
## ever contributing to `bins` — silently wrong values, no error), and there is
## no per-stat array copy on a path that only wants a handful of edges.
func collect_formula_edges(out: Dictionary) -> void:
	for m in _modifiers:
		m.collect_formula_edges(out)


## Take over [param src]'s applied-modifier list and its per-modifier
## contribution ledger. The clone half of [method StatBoard.clone_live]'s bin
## copy, and **not optional next to it**: the bins are a fold over `_modifiers`,
## and [method _resync_bins_if_trivial] wipes and rebuilds them from that list
## the moment it holds 0 or 1 entries — so a stat that carried a tally but an
## empty list threw the tally away on the very next [method add_modifier].
##
## Shallow on purpose: the [StatModifier] instances are SHARED with [param src],
## which is safe because a modifier is stateless and may live on N boards at
## once (#377) — the same one-level-deep rule `bins.multipliers` already
## follows. `_last_contrib` is keyed by those same instances, so a shallow
## dictionary copy transfers intact.
##
## Deliberately does NOT subscribe to each modifier's `changed` — subscribing to
## a SHARED instance is what bleeds a shadow's recomputes back onto the live
## board, and what keeps this [Stat] alive for as long as that instance lives.
## Reactivity is restored by [method localize_formula_modifiers], which first
## replaces the instances that need it with private copies (#506).
##
## Tell-don't-ask, same reason there is no `get_modifiers()`: the list never
## leaves the [Stat].
func adopt_modifier_list(src: Stat) -> void:
	_modifiers = src._modifiers.duplicate()
	_last_contrib = src._last_contrib.duplicate()


## Give this stat its OWN copy of every formula-bearing modifier it holds, and
## subscribe to the copies. The reactivity half of [method StatBoard.clone_live]
## (#506); [param known] is the board's `orig -> copy` map, read AND written here
## so one original yields one copy no matter how many stats hold it.
##
## [b]Why copies rather than binding the shared instances.[/b] The chain a
## formula needs is `source stat -> modifier -> target stat`. Binding a shared
## modifier makes that chain span two boards: a shadow's `constitution` moving
## would `emit_changed()` on an instance the LIVE board's stats are subscribed
## to, firing real recomputes and `value_changed` storms for a simulation — and
## the [Callable] on the live modifier's `changed` would pin this [Stat] in
## memory for as long as the shared modifier lives, which no shadow teardown
## could ever undo (the anchor belongs to the live board). With a private copy
## every edge of the chain is owned by this board, so the shadow reacts fully,
## the source board never hears a thing, and everything the clone allocated
## stays collectable from the clone's own side.
##
## [b]Only formula-bearing modifiers are copied.[/b] A static modifier has no
## source to watch, so it stays shared and unsubscribed — which means a clone
## does NOT track later `value` edits to the live statics it borrowed. That
## asymmetry is deliberate: a shadow is a frozen world plus its own mutations,
## and copying all N modifiers to hear about edits nobody makes mid-rollout
## would pay the cost #498's bench exists to avoid.
##
## Swaps the instance everywhere it is keyed by identity — `_modifiers`,
## `_last_contrib`, `bins.multipliers`, `bins.winning_set`. Missing one of those
## does not produce a wrong value (the pipeline resolves against `bins.board`
## either way); it produces a modifier that cannot be revoked by the handle a
## caller holds, which is worse for being invisible.
func localize_formula_modifiers(known: Dictionary) -> void:
	for i in _modifiers.size():
		var orig := _modifiers[i]
		if orig.formula == null:
			continue
		var copy: StatModifier = known.get(orig)
		if copy == null:
			# Shallow: the StatFormula is stateless (it computes against a board
			# passed in), so sharing it costs nothing and copies nothing deep.
			copy = orig.duplicate() as StatModifier
			known[orig] = copy
		_modifiers[i] = copy
		if _last_contrib.has(orig):
			_last_contrib[copy] = _last_contrib[orig]
			_last_contrib.erase(orig)
		var mi := bins.multipliers.find(orig)
		if mi >= 0:
			bins.multipliers[mi] = copy
		if bins.winning_set == orig:
			bins.winning_set = copy
		var cb := _on_dependent_modifier_changed.bind(copy)
		if not copy.changed.is_connected(cb):
			copy.changed.connect(cb)


## Drop this stat's subscription to every modifier it holds. The [Stat] half of
## [method StatBoard.release] (#514) — tell-don't-ask again, since `_modifiers`
## never leaves the [Stat].
##
## Deliberately leaves `_modifiers`, `_last_contrib` and [member bins] alone: a
## released board is inert, not blank, and clearing the list would run
## [method _resync_bins_if_trivial]'s wipe for no reason. This only cuts the
## wires.
func release_modifier_subscriptions() -> void:
	for m in _modifiers:
		var cb := _on_dependent_modifier_changed.bind(m)
		if m.changed.is_connected(cb):
			m.changed.disconnect(cb)


## [param board] is the board this modifier is being applied on — remembered
## on [member _board] for later reactive recomputation. Optional (defaults to
## null) so a caller adding a purely static modifier directly to a bare Stat
## (no board in scope, e.g. several unit tests) doesn't need to fabricate one;
## a formula-bound modifier added that way degrades to its static `value`,
## same as an always-unbound modifier did before #377.
func add_modifier(m: StatModifier, board: StatBoard = null) -> void:
	if board != null:
		_board = board
		bins.board = board
	if m in _modifiers:
		return
	_modifiers.append(m)
	# Resource.changed fires from the value setter, from any other emit_changed
	# call on the modifier, and from formula-source updates (StatModifier's
	# _on_source_changed re-emits `changed`). One subscription covers all three.
	m.changed.connect(_on_dependent_modifier_changed.bind(m))
	match m.operation:
		StatModifier.Operation.SET:
			if bins.winning_set == null or m.priority >= bins.winning_set.priority:
				bins.winning_set = m
		StatModifier.Operation.MULTIPLY:
			bins.multipliers.append(m)
		_:
			var v := m.get_effective_value(_board)
			_last_contrib[m] = v
			_apply_bin_delta(m.operation, 0.0, v)
	_resync_bins_if_trivial()
	_emit_value_changed()


func remove_modifier(m: StatModifier, board: StatBoard = null) -> void:
	if board != null:
		_board = board
		bins.board = board
	_modifiers.erase(m)
	var cb := _on_dependent_modifier_changed.bind(m)
	if m.changed.is_connected(cb):
		m.changed.disconnect(cb)
	match m.operation:
		StatModifier.Operation.SET:
			if m == bins.winning_set:
				bins.winning_set = _find_winning_set()
		StatModifier.Operation.MULTIPLY:
			bins.multipliers.erase(m)
		_:
			var old: float = _last_contrib.get(m, m.get_effective_value(_board))
			_last_contrib.erase(m)
			_apply_bin_delta(m.operation, old, 0.0)
	_resync_bins_if_trivial()
	_emit_value_changed()


## A modifier this stat depends on has changed — its `value` was edited or a
## formula source moved. Re-deltify the additive bins through the same path as
## add/remove. SET winners and MULTIPLY entries read live in get_value(), so
## no bin maintenance is needed for those ops.
func _on_dependent_modifier_changed(m: StatModifier) -> void:
	var op := m.operation
	if op != StatModifier.Operation.SET and op != StatModifier.Operation.MULTIPLY:
		var old: float = _last_contrib.get(m, 0.0)
		var new_v := m.get_effective_value(_board)
		_last_contrib[m] = new_v
		_apply_bin_delta(op, old, new_v)
	_emit_value_changed()


func _apply_bin_delta(op: int, old: float, new_v: float) -> void:
	var delta := new_v - old
	match op:
		StatModifier.Operation.ADD_BASE:
			bins.base_add += delta
		StatModifier.Operation.INCREASE:
			bins.increase_sum += delta
		StatModifier.Operation.ADD_BONUS:
			bins.bonus_add += delta


## Free anti-drift: at 0 or 1 modifiers the bins have a known exact form, so
## reset them from scratch. Cheap, covers any residual FP error from churn.
func _resync_bins_if_trivial() -> void:
	if _modifiers.size() > 1:
		return
	bins.base_add = 0.0
	bins.increase_sum = 0.0
	bins.bonus_add = 0.0
	bins.multipliers.clear()
	_last_contrib.clear()
	if _modifiers.is_empty():
		return
	var m := _modifiers[0]
	match m.operation:
		StatModifier.Operation.SET:
			pass  # bins.winning_set already correct.
		StatModifier.Operation.MULTIPLY:
			bins.multipliers.append(m)
		_:
			var v := m.get_effective_value(_board)
			_last_contrib[m] = v
			_apply_bin_delta(m.operation, 0.0, v)


func _find_winning_set() -> StatModifier:
	var best: StatModifier = null
	for m in _modifiers:
		if m.operation == StatModifier.Operation.SET:
			if best == null or m.priority >= best.priority:
				best = m
	return best


## Computed value: base + modifier pipeline, coerced to the definition's value_type.
## ADD_BASE / INCREASE / ADD_BONUS read O(1) from running bins; MULTIPLY walks
## its (typically tiny) list to avoid the divide-on-remove drift trap.
## Delegates the math to ModifierBins.compute so single-source (this) and
## multi-source (entity + node-board) reads share the one pipeline implementation.
func get_value() -> Variant:
	return _coerce(ModifierBins.compute(base_value, [bins]))


## Read this stat through a formula accessor — the ONLY door the formula
## layer has into a stat's extra state (#333). `&""` is the computed value /
## cap (the bare-token form, what every formula reads today). Named
## accessors are answered by the subclass's [method accessors] override:
## [PoolStat] answers `current`; [SkillPointStat] adds `wounded` / `staked` /
## `used`; [SurplusPoolStat] adds `surplus` / `available`. Subclasses expose
## their own bins by overriding [method accessors]; the formula layer never
## learns which subclasses exist.
##
## An unknown name warns and falls through to [method get_value] — never
## fails silently, never errors. Same shape as the modifier-pipeline
## "reject-and-keep-running" rule: a typo in a formula token degrades to the
## computed value with a warning, not a hard crash mid-pipeline.
func read_accessor(accessor_name: StringName) -> Variant:
	if accessor_name == &"":
		return get_value()
	var d := accessors()
	if d.has(accessor_name):
		return d[accessor_name].call(self)
	push_warning("Stat '%s' has no accessor '%s'" % [definition.id if definition != null else &"?", accessor_name])
	return get_value()


## The accessor names this stat answers to — `{name: callable(stat) -> Variant}`
## for [method read_accessor]. A bare scalar returns `{}`; subclasses override
## and compose through `super.accessors()` + `.merge()`, so an inherited name
## being shadowed by a subclass is a visible `.merge()` overwrite (the same
## discoverability posture as [method CoreClass.load_all]'s directory scan:
## the list lives where the data lives, not in a parallel hand-maintained
## registry the formula layer would have to track).
##
## Each entry's [Callable] is a lambda over the stat instance — `func(s): return
## s.current` — chosen over `get.bind(...)` because a real member access is
## statically checked at parse time (a typo `s.wounde` fails the script)
## where `s.get(&"wounde")` would silently return null. Rebuilding the dict
## per call is trivially cheap (a handful of entries, resolved on formula
## bind, not per-frame); the entries cannot live as a `const` because a
## `Callable` literal is not a constant expression in GDScript 4.7.
func accessors() -> Dictionary[StringName, Callable]:
	return {}


## Inspector niceties -------------------------------------------------------
##
## Synthetic read-only `computed_value` row shows the post-pipeline result
## live, so modifier math is verifiable without entering play mode.
## Subclasses override `_computed_display()` to enrich the readout
## (e.g. PoolStat shows "current / max").

const _COMPUTED_KEY := &"computed_value"


func _get_property_list() -> Array[Dictionary]:
	return [{
		"name": _COMPUTED_KEY,
		"type": TYPE_STRING,
		"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY,
	}]


func _get(property: StringName) -> Variant:
	if property == _COMPUTED_KEY:
		return _computed_display()
	return null


func _computed_display() -> String:
	return str(get_value())


func _sync_resource_name() -> void:
	if definition != null and definition.id != &"":
		resource_name = String(definition.id)


func _to_string() -> String:
	var id_str := String(definition.id) if definition != null else "?"
	var label := "Stat"
	var s := get_script() as Script
	if s != null and s.get_global_name() != &"":
		label = String(s.get_global_name())
	return "<%s:%s=%s>" % [label, id_str, str(get_value())]


func _coerce(v: float) -> Variant:
	if definition == null:
		return v
	match definition.value_type:
		StatDef.ValueType.INT:
			return roundi(v)
		StatDef.ValueType.BOOL:
			return v != 0.0
		_:
			return v
