@tool
class_name CombatCardMagic
extends CombatReadoutCard
## Magic readout: selected spell's potency/instance + hop reach ("rare" tag
## when [member PropagationConfig.max_hops] is nonzero). Bound to whichever
## spell [BattleSystem.selected_spell] currently points at — null-safe (no
## spell selected shows zeros).

@onready var _potency_row: CombatValueRow = %PotencyRow
@onready var _reach_row: CombatValueRow = %ReachRow

var _battle_system: BattleSystem


func bind(battle_system: BattleSystem) -> void:
	_battle_system = battle_system
	if _battle_system == null:
		return
	_battle_system.selected_spell_changed.connect(_refresh)
	_refresh(_battle_system.selected_spell)


func _refresh(spell: SpellDef = null) -> void:
	if spell == null and _battle_system != null:
		spell = _battle_system.selected_spell
	if spell == null:
		_potency_row.set_value(0.0)
		_reach_row.set_value(0.0)
		_reach_row.set_sliver("")
		return
	_potency_row.set_value(spell.base_damage)
	var hops := spell.propagation.max_hops if spell.propagation != null else 0
	_reach_row.set_value(float(hops), " hops")
	_reach_row.set_sliver("rare" if hops > 0 else "")
