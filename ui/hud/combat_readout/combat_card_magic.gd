@tool
class_name CombatCardMagic
extends CombatReadoutCard
## Magic readout: the CASTER's magic stats, never the cast — the per-cast facts
## (the spell's sections, its affinity) live in the magic tray's configure view.
##
## Potency is the caster's `spell_damage`: %PotencyRow is a self-binding stat
## row ([member CombatValueRow.stat_id]), so it also shows a hovered owned
## node's local override. Reach DESCRIBES the caster's `cast_range_hops`
## pipeline as text ("(X+3) × 1.5") via [method Stat.resolve_with] — the card
## never assembles bins itself, the fold belongs to the stat.

@onready var _reach_row: CombatValueRow = %ReachRow


@warning_ignore("unused_parameter")
func _bind(board: StatBoard, owner_entity: Entity = null) -> void:
	var reach: Stat = board.get_stat(&"cast_range_hops")
	if reach != null:
		_binds.link(reach.value_changed, _refresh)


func _refresh() -> void:
	super._refresh()
	var reach: Stat = _board.get_stat(&"cast_range_hops") if _board != null else null
	if reach != null:
		_reach_row.set_text(reach.resolve_with([]).describe())
	else:
		_reach_row.set_value(0.0)
	_reach_row.set_sliver("")
