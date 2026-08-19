@tool
class_name CombatCardCrit
extends CombatReadoutCard
## Crit readout: chance to crit + crit damage multiplier.
##
## Never mode-highlighted (not tied to an AttackMode, same as Defense) — crit
## applies equally whether the plan is melee/ranged/magic or manage mode has
## no plan selected at all, so there's no "select Crit" input channel.


@onready var _chance_row: CombatValueRow = %ChanceRow
@onready var _multiplier_row: CombatValueRow = %MultiplierRow


@warning_ignore("unused_parameter")
func _bind(board: StatBoard, owner_entity: Entity = null) -> void:
	if board.crit_chance != null:
		board.crit_chance.value_changed.connect(_refresh)
	if board.crit_multiplier != null:
		board.crit_multiplier.value_changed.connect(_refresh)


func _refresh() -> void:
	if _board == null:
		return
	var chance_v: float = float(_board.crit_chance.value) if _board.crit_chance != null else 0.0
	var mult_v: float = float(_board.crit_multiplier.value) if _board.crit_multiplier != null else 0.0
	_chance_row.set_value(chance_v * 100.0, "%")
	_multiplier_row.set_value(mult_v, "x")

	# #119 — node-local override preview.
	var chance_ov: Variant = _local_override_or_null(&"crit_chance", chance_v)
	if chance_ov != null:
		_chance_row.show_override(float(chance_ov) * 100.0)
	else:
		_chance_row.clear_override()

	var mult_ov: Variant = _local_override_or_null(&"crit_multiplier", mult_v)
	if mult_ov != null:
		_multiplier_row.show_override(mult_ov)
	else:
		_multiplier_row.clear_override()
