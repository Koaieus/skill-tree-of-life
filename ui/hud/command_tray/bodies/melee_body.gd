@tool
class_name MeleeBody
extends CommandTrayBodyBase
## Melee tab content (#114): blade-builder hint w/ [CapacityBlips] pips,
## Swing CW/CCW toggle, Launch. Only ever bound while [BattleSystem]'s
## attack mode is MELEE, so [member CommandTrayBodyBase._battle_system]'s
## plan is a [MeleeAttackPlan] whenever this body exists.

@onready var _hint: Label = %Hint
@onready var _blips: CapacityBlips = %Blips
@onready var _count_label: Label = %CountLabel
@onready var _swing_button: Button = %SwingButton
@onready var _reset_button: Button = %ResetButton
@onready var _launch_button: LaunchAttackButton = %LaunchButton


func _on_bound() -> void:
	_swing_button.pressed.connect(_on_swing_pressed)
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


func _on_swing_pressed() -> void:
	_battle_system.next_melee_cw = not _battle_system.next_melee_cw
	var plan := _battle_system.attack_plan as MeleeAttackPlan
	if plan != null:
		plan.swing_cw = _battle_system.next_melee_cw
	_refresh()


func _refresh() -> void:
	var plan := _battle_system.attack_plan as MeleeAttackPlan
	var max_blades := plan.max_blades() if plan != null else 1
	var count := plan.blade_nodes.size() if plan != null else 0
	_hint.text = "Right-click a pivot, left-click to grow the blade up to %d connected nodes. The shape is copied and swung once." % max_blades
	_blips.max_count = max_blades
	_blips.count = count
	_count_label.text = "pivot + %d" % count
	var cw: bool = _battle_system.next_melee_cw
	_swing_button.text = "↻ Swing CW" if cw else "↺ Swing CCW"
	var can_act := _input_ctl == null or _input_ctl.can_player_act()
	_launch_button.set_enabled(plan != null and plan.is_valid() and can_act)
