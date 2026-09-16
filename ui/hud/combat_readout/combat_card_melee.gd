@tool
class_name CombatCardMelee
extends CombatReadoutCard
## Melee readout: blade size as [CapacityBlips] diamond pips, blade damage,
## and blunting (spike-pop power against a defender's spikes, #778). Damage
## and blunting are plain scene-authored [CombatValueRow]s (#913) — only the
## blips need subclass code, since [CapacityBlips] isn't a row.

@onready var _size_blips: CapacityBlips = %SizeBlips


@warning_ignore("unused_parameter")
func _bind(board: StatBoard, owner_entity: Entity = null) -> void:
	super._bind(board, owner_entity)
	if board.blade_size != null:
		_binds.link(board.blade_size.value_changed, _refresh)


func _refresh() -> void:
	super._refresh()
	if _board == null or _board.blade_size == null:
		return
	var size_v: int = int(_board.blade_size.value)
	_size_blips.max_count = size_v
	_size_blips.count = size_v
