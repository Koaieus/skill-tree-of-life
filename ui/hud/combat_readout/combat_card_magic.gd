@tool
class_name CombatCardMagic
extends CombatReadoutCard
## Magic readout: selected spell's potency/instance + hop reach ("rare" tag
## when [member PropagationConfig.max_hops] is nonzero). Bound to whichever
## spell [BattleSystem.selected_spell] currently points at — null-safe (no
## spell selected shows zeros).
##
## Potency is the [b]computed seed[/b] — [code]spell_damage × power[/code] for
## the bound caster — not the raw [member SpellDef.power] coefficient, which is
## meaningless on its own (D-32). It therefore moves when INT does, which is
## why the card also listens to the stat.

# TODO: Complete refactor to inherited scene like MeleeCard and RangedCard

@onready var _potency_row: CombatValueRow = %PotencyRow
@onready var _reach_row: CombatValueRow = %ReachRow

var _battle_system: BattleSystem

var _spell: SpellDef:
	get = _get_spell, set = _set_spell 


func _bind(board: StatBoard, owner_entity: Entity = null) -> void:
	if board.spell_damage != null:
		board.spell_damage.value_changed.connect(_refresh)
	if _battle_system != null:
		_battle_system.selected_spell_changed.connect(_set_spell)

func _get_spell() -> SpellDef:
	if _spell != null:
		return _spell
	return _battle_system.selected_spell if _battle_system else null
	
func _set_spell(spell: SpellDef = null):
	if spell != null and spell == _spell: return
	_spell = spell
	_refresh()

func _refresh() -> void:
	var spell := _spell
	if spell == null:
		_potency_row.set_value(0.0)
		_reach_row.set_value(0.0)
		_reach_row.set_sliver("")
		return
	_potency_row.set_value(SpellResolver.impact_damage(spell, null, _board))
	var hops := spell.propagation.max_hops if spell.propagation != null else 0
	_reach_row.set_value(float(hops), " hops")
	_reach_row.set_sliver("rare" if hops > 0 else "")
