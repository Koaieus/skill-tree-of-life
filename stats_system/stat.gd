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
@export var base_value: float = 0.0:
	set(v):
		if v == base_value:
			return
		base_value = v
		# Computed value moves with base_value; notify subscribers (UI, formula
		# modifiers watching this stat) so reactive paths stay coherent when
		# scripts write base_value directly.
		value_changed.emit()

var _modifiers: Array[StatModifier] = []

## Per-operation pipeline bins, factored into ModifierBins so multi-source
## reads (e.g. LocalStat layering on top of an entity-side Stat) can compose
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

## Shorthand for `get_value()`. Delegates so subclass overrides win — e.g.
## `pool.value` returns the pool's current via PoolStat's override.
var value: Variant:
	get: return get_value()


func _init() -> void:
	# Editor: refresh the computed_value inspector row whenever the pipeline result changes.
	if Engine.is_editor_hint():
		value_changed.connect(notify_property_list_changed)


func add_modifier(m: StatModifier) -> void:
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
			var v := m.get_effective_value()
			_last_contrib[m] = v
			_apply_bin_delta(m.operation, 0.0, v)
	_resync_bins_if_trivial()
	value_changed.emit()


func remove_modifier(m: StatModifier) -> void:
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
			var old: float = _last_contrib.get(m, m.get_effective_value())
			_last_contrib.erase(m)
			_apply_bin_delta(m.operation, old, 0.0)
	_resync_bins_if_trivial()
	value_changed.emit()


## A modifier this stat depends on has changed — its `value` was edited or a
## formula source moved. Re-deltify the additive bins through the same path as
## add/remove. SET winners and MULTIPLY entries read live in get_value(), so
## no bin maintenance is needed for those ops.
func _on_dependent_modifier_changed(m: StatModifier) -> void:
	var op := m.operation
	if op != StatModifier.Operation.SET and op != StatModifier.Operation.MULTIPLY:
		var old: float = _last_contrib.get(m, 0.0)
		var new_v := m.get_effective_value()
		_last_contrib[m] = new_v
		_apply_bin_delta(op, old, new_v)
	value_changed.emit()


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
			var v := m.get_effective_value()
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
## multi-source (LocalStat) reads share the one pipeline implementation.
func get_value() -> Variant:
	return _coerce(ModifierBins.compute(base_value, [bins]))


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
