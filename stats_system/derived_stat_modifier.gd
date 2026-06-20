@tool
class_name DerivedStatModifier
extends StatModifier

## A modifier whose effective value is computed from other stats via a
## pluggable StatFormula. `value` (inherited) is the fallback when
## unbound or formula is null.
##
## Lifecycle:
##   StatBoard.add_modifier(m)    → calls m.bind(board)  → subscribes to sources
##   StatBoard.remove_modifier(m) → calls m.unbind()     → unsubscribes
##
## WARNING: instances carry mutable binding state (_board, _bound_sources,
## _propagating) and MUST NOT be shared across entities. If the same .tres
## needs to be on multiple entities, call .duplicate(true) on assignment.

signal source_value_changed

@export var formula: StatFormula = null

var _board: StatBoard = null
var _bound_sources: Array[Stat] = []
var _propagating: bool = false


func get_effective_value() -> float:
	if formula != null and _board != null:
		return formula.compute(_board)
	return value


func bind(board: StatBoard) -> void:
	_board = board
	if formula == null:
		return
	for id in formula.get_input_ids():
		var s := board.get_stat(id)
		if s == null:
			push_warning("DerivedStatModifier: source stat '%s' not found in board" % id)
			continue
		if not s.value_changed.is_connected(_on_source_changed):
			s.value_changed.connect(_on_source_changed)
		_bound_sources.append(s)


func unbind() -> void:
	for s in _bound_sources:
		if s.value_changed.is_connected(_on_source_changed):
			s.value_changed.disconnect(_on_source_changed)
	_bound_sources.clear()
	_board = null


func _on_source_changed() -> void:
	if _propagating:
		return  # cycle guard: stops A→B→A from looping indefinitely
	_propagating = true
	source_value_changed.emit()
	_propagating = false
