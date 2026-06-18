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

@export var definition: StatDef:
	set(v):
		definition = v
		_sync_resource_name()
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


func _init() -> void:
	# Editor: refresh the computed_value inspector row whenever the pipeline result changes.
	if Engine.is_editor_hint():
		value_changed.connect(notify_property_list_changed)


func add_modifier(m: StatModifierDef) -> void:
	_modifiers.append(m)
	if m is DerivedModifierDef:
		(m as DerivedModifierDef).source_value_changed.connect(_on_dependent_modifier_changed)
	if m.operation == StatModifierDef.Operation.SET:
		if _winning_set == null or m.priority >= _winning_set.priority:
			_winning_set = m
	value_changed.emit()


func remove_modifier(m: StatModifierDef) -> void:
	_modifiers.erase(m)
	if m is DerivedModifierDef:
		var dm := m as DerivedModifierDef
		if dm.source_value_changed.is_connected(_on_dependent_modifier_changed):
			dm.source_value_changed.disconnect(_on_dependent_modifier_changed)
	if m == _winning_set:
		_winning_set = _find_winning_set()
	value_changed.emit()


func _on_dependent_modifier_changed() -> void:
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
		return _coerce(_winning_set.get_effective_value())
	var base_add := 0.0
	var increase_sum := 0.0
	var mult := 1.0
	var bonus_add := 0.0
	for m in _modifiers:
		match m.operation:
			StatModifierDef.Operation.ADD_BASE:
				base_add += m.get_effective_value()
			StatModifierDef.Operation.INCREASE:
				increase_sum += m.get_effective_value()
			StatModifierDef.Operation.MULTIPLY:
				mult *= m.get_effective_value()
			StatModifierDef.Operation.ADD_BONUS:
				bonus_add += m.get_effective_value()
			# SET handled via _winning_set cache.
	var raw: float = (base_value + base_add) * (1.0 + increase_sum / 100.0) * mult + bonus_add
	return _coerce(raw)


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
