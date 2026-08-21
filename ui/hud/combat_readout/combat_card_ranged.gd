@tool
class_name CombatCardRanged
extends CombatReadoutCard
## Ranged readout: damage/leaf + firing range (px).
##
## Reads `ranged_damage` and `range` from the entity's StatBoard — both
## are formula-driven StatDefs, so the card stays dumb and just displays.

@onready var _damage_row: CombatValueRow = %DamageRow
@onready var _range_row: CombatValueRow = %RangeRow


@warning_ignore("unused_parameter")
func _bind(board: StatBoard, owner_entity: Entity = null) -> void:
	if board.ranged_damage != null:
		_binds.link(board.ranged_damage.value_changed, _refresh)
	if board.range != null:
		_binds.link(board.range.value_changed, _refresh)
	
	
func _refresh() -> void:
	if _board == null:
		return
	var dmg: float = float(_board.ranged_damage.value) if _board.ranged_damage != null else 0.0
	_damage_row.set_value(dmg)

	var range_v: float = float(_board.range.value) if _board.range != null else 0.0
	_range_row.set_value(range_v, " px")

	# #119 — node-local override preview.
	var ov: Variant = _local_override_or_null(&"ranged_damage", dmg)
	if ov != null:
		_damage_row.show_override(ov)
	else:
		_damage_row.clear_override()

	ov = _local_override_or_null(&"range", range_v)
	if ov != null:
		_range_row.show_override(ov)
	else:
		_range_row.clear_override()
