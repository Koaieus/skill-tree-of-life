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
##   INT stats round once, here. See StatModifierDef for value-scale conventions.

signal value_changed

@export var definition: StatDef
@export var base_value: float = 0.0

var _modifiers: Array[StatModifierDef] = []
## Cached SET winner. SET is the only op where order matters; tracking the
## winner on insert/remove lets get_value() early-return in O(1). Future:
## promote to per-op bins when a stat shows up in a hot path that reads
## between mutations.
var _winning_set: StatModifierDef = null

## Shorthand for `get_value()`. Delegates so subclass overrides win — e.g.
## `pool.value` returns the pool's current via PoolStat's override.
var value: Variant:
	get: return get_value()


func add_modifier(m: StatModifierDef) -> void:
	_modifiers.append(m)
	if m.operation == StatModifierDef.Operation.SET:
		if _winning_set == null or m.priority >= _winning_set.priority:
			_winning_set = m
	value_changed.emit()


func remove_modifier(m: StatModifierDef) -> void:
	_modifiers.erase(m)
	if m == _winning_set:
		_winning_set = _find_winning_set()
	value_changed.emit()


func _find_winning_set() -> StatModifierDef:
	var best: StatModifierDef = null
	for m in _modifiers:
		if m.operation == StatModifierDef.Operation.SET:
			if best == null or m.priority >= best.priority:
				best = m
	return best


## Computed value: base + modifier pipeline, coerced to the definition's value_type.
func get_value() -> Variant:
	if _winning_set != null:
		return _coerce(_winning_set.value)
	var base_add := 0.0
	var increase_sum := 0.0
	var mult := 1.0
	var bonus_add := 0.0
	for m in _modifiers:
		match m.operation:
			StatModifierDef.Operation.ADD_BASE:
				base_add += m.value
			StatModifierDef.Operation.INCREASE:
				increase_sum += m.value
			StatModifierDef.Operation.MULTIPLY:
				mult *= m.value
			StatModifierDef.Operation.ADD_BONUS:
				bonus_add += m.value
			# SET handled via _winning_set cache.
	var raw: float = (base_value + base_add) * (1.0 + increase_sum / 100.0) * mult + bonus_add
	return _coerce(raw)


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
