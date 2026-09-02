@tool
class_name CombatCardDefense
extends CombatReadoutCard
## Defense readout: armor + damage floor ([Mitigation]'s `min_damage_taken`).
##
## Never mode-highlighted (not tied to an AttackMode) — the shell still
## flashes it via [method flash_unmute] on any relevant stat change.

# Inherited-scene cutover unfinished relative to MeleeCard/RangedCard — see #723.


@onready var _armor_row: CombatValueRow = %ArmorRow
@onready var _floor_row: CombatValueRow = %FloorRow


@warning_ignore("unused_parameter")
func _bind(board: StatBoard, owner_entity: Entity = null) -> void:
	if board.armor != null:
		_binds.link(board.armor.value_changed, _refresh)
	if board.min_damage_taken != null:
		_binds.link(board.min_damage_taken.value_changed, _refresh)


func _refresh() -> void:
	if _board == null:
		return
	var armor_v: float = float(_board.armor.value) if _board.armor != null else 0.0
	var floor_v: float = float(_board.min_damage_taken.value) if _board.min_damage_taken != null else 0.0
	_armor_row.set_value(armor_v)
	_floor_row.set_value(floor_v)

	# #119 — node-local override preview (armor/min_damage_taken are both
	# common node-local modifier targets per stats-system.md).
	var armor_ov: Variant = _local_override_or_null(&"armor", armor_v)
	if armor_ov != null:
		_armor_row.show_override(armor_ov)
	else:
		_armor_row.clear_override()
	var floor_ov: Variant = _local_override_or_null(&"min_damage_taken", floor_v)
	if floor_ov != null:
		_floor_row.show_override(floor_ov)
	else:
		_floor_row.clear_override()
