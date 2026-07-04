@tool
class_name MagicBody
extends CommandTrayBodyBase
## Magic tab content (#114): reuses [SpellPickerBar]/[SpellPickerButton]
## verbatim (mana-cost/lock-state logic already lives there — see #114's
## explicit "don't rebuild the spell bar from scratch") + a Launch button
## whose label mirrors the currently-equipped spell.

@onready var _context_label: Label = %ContextLabel
@onready var _spell_bar: SpellPickerBar = %SpellPickerBar
@onready var _launch_button: LaunchAttackButton = %LaunchButton


func _on_bound() -> void:
	_spell_bar.bind_spellbook(_player.spellbook)
	_spell_bar.spell_selected.connect(_on_spell_selected)
	_battle_system.selected_spell_changed.connect(_spell_bar.sync_selected)
	_launch_button.pressed.connect(_battle_system.launch_attack)
	_battle_system.attack_plan_state_changed.connect(_refresh)
	if _input_ctl != null:
		_input_ctl.player_can_act_changed.connect(_on_can_act_changed)
		_spell_bar.set_enabled(_input_ctl.can_player_act())
	if _battle_system.selected_spell != null:
		_spell_bar.sync_selected(_battle_system.selected_spell)
	_refresh()


func teardown() -> void:
	if _battle_system.selected_spell_changed.is_connected(_spell_bar.sync_selected):
		_battle_system.selected_spell_changed.disconnect(_spell_bar.sync_selected)
	if _battle_system.attack_plan_state_changed.is_connected(_refresh):
		_battle_system.attack_plan_state_changed.disconnect(_refresh)
	if _input_ctl != null and _input_ctl.player_can_act_changed.is_connected(_on_can_act_changed):
		_input_ctl.player_can_act_changed.disconnect(_on_can_act_changed)


func _on_spell_selected(spell: SpellDef) -> void:
	_battle_system.selected_spell = spell


func _on_can_act_changed(can_act: bool) -> void:
	_spell_bar.set_enabled(can_act)
	_refresh()


func _refresh() -> void:
	var plan := _battle_system.attack_plan as MagicAttackPlan
	var board := _player.stat_board if _player != null else null
	var mana: float = float(board.mana.current) if board != null and board.mana != null else 0.0
	var degree := 0
	if plan != null and plan.source != null and _player.navigator != null:
		degree = _player.navigator.get_degree(plan.source)
	_context_label.text = "source degree %d · mana %d" % [degree, int(mana)]
	if plan != null:
		_spell_bar.update_gating_context(plan.attacker, plan.source)
	var spell_name := plan.spell.name if plan != null and plan.spell != null else "Spell"
	_launch_button.text = "Cast %s" % spell_name
	var can_act := _input_ctl == null or _input_ctl.can_player_act()
	_launch_button.set_enabled(plan != null and plan.is_valid() and can_act)
