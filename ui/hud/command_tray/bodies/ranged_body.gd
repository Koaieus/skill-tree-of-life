@tool
class_name RangedBody
extends CommandTrayBodyBase
## Ranged tab content (#114): target hint + firing-leaves count, Launch.
##
## Reads `ranged_damage` and `range` from the player's StatBoard — both
## are formula-driven StatDefs, so the tray stays dumb and just displays.

@onready var _leaves_value: Label = %LeavesValue
@onready var _damage_range_label: Label = %DamageRangeLabel
@onready var _reset_button: Button = %ResetButton
@onready var _launch_button: LaunchAttackButton = %LaunchButton


func _on_bound() -> void:
	_reset_button.pressed.connect(_battle_system.reset_plan)
	_launch_button.pressed.connect(_battle_system.launch_attack)
	_battle_system.attack_plan_state_changed.connect(_refresh)
	if _input_ctl != null:
		_input_ctl.player_can_act_changed.connect(_refresh.unbind(1))
	_refresh()


func teardown() -> void:
	if _battle_system.attack_plan_state_changed.is_connected(_refresh):
		_battle_system.attack_plan_state_changed.disconnect(_refresh)
	if _input_ctl != null and _input_ctl.player_can_act_changed.is_connected(_refresh.unbind(1)):
		_input_ctl.player_can_act_changed.disconnect(_refresh.unbind(1))


func _refresh() -> void:
	var plan := _battle_system.attack_plan as RangedAttackPlan
	var board := _player.stat_board if _player != null else null
	var dmg: float = float(board.ranged_damage.value) if board != null and board.ranged_damage != null else 0.0
	var range_v: float = float(board.range.value) if board != null and board.range != null else 0.0
	_damage_range_label.text = "%d dmg/leaf · %d px" % [int(dmg), int(range_v)]
	var leaves := plan.get_reaching_firing_positions().size() if plan != null else 0
	_leaves_value.text = str(leaves)
	var can_act := _input_ctl == null or _input_ctl.can_player_act()
	_launch_button.set_enabled(plan != null and plan.is_valid() and can_act)
