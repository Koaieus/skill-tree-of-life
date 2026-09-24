@tool
class_name CombatCardMagic
extends CombatReadoutCard
## Magic readout: selected spell's potency/instance + hop reach ("rare" tag
## when [member PropagationConfig.max_hops] is nonzero). Bound to whichever
## spell [BattleSystem.selected_spell] currently points at — null-safe.
##
## The Reach row has two tiers. No spell selected: the row DESCRIBES the
## caster's `cast_range_hops` pipeline as text ("(X+3) × 1.5") via
## [method Stat.resolve_with] — the card never assembles bins itself, the
## fold belongs to the stat. Spell selected: the number
## [method SpellRangeRules.reach] answers for the authored `max_hops`, never
## the raw authored value.
##
## Potency is the [b]computed seed[/b] — [code]spell_damage × power[/code] for
## the bound caster — not the raw [member SpellDef.power] coefficient, which is
## meaningless on its own (D-32). It therefore moves when INT does, which is
## why the card also listens to the stat.

@onready var _potency_row: CombatValueRow = %PotencyRow
@onready var _reach_row: CombatValueRow = %ReachRow

var _battle_system: BattleSystem

var _spell: SpellDef:
	get = _get_spell, set = _set_spell 


@warning_ignore("unused_parameter")
func _bind(board: StatBoard, owner_entity: Entity = null) -> void:
	if board.spell_damage != null:
		_binds.link(board.spell_damage.value_changed, _refresh)
	var reach: Stat = board.get_stat(&"cast_range_hops")
	if reach != null:
		_binds.link(reach.value_changed, _refresh)
	if _battle_system != null:
		_binds.link(_battle_system.selected_spell_changed, _set_spell)

func _get_spell() -> SpellDef:
	if _spell != null:
		return _spell
	return _battle_system.selected_spell if _battle_system else null
	
func _set_spell(spell: SpellDef = null):
	if spell != null and spell == _spell: return
	_spell = spell
	_refresh()

func _refresh() -> void:
	super._refresh()
	var spell := _spell
	_potency_row.set_value(SpellResolver.impact_damage(spell, null, _board))
	if spell == null:
		var reach: Stat = _board.get_stat(&"cast_range_hops") if _board != null else null
		if reach != null:
			_reach_row.set_text(reach.resolve_with([]).describe())
		else:
			_reach_row.set_value(0.0)
		_reach_row.set_sliver("")
		return
	var authored: float = spell.propagation.max_hops if spell.propagation != null else 0.0
	if is_inf(authored):
		_reach_row.set_text("∞ hops")
	else:
		var hops := SpellRangeRules.reach(&"cast_range_hops", authored, _owner_entity,
				_hover_node, _board)
		_reach_row.set_value(hops, " hops")
	_reach_row.set_sliver("rare" if authored > 0 else "")
