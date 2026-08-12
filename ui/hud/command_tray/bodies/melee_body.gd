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
@onready var _upgrade_row: HBoxContainer = %UpgradeRow
@onready var _swing_button: Button = %SwingButton
@onready var _reset_button: Button = %ResetButton
@onready var _launch_button: LaunchAttackButton = %LaunchButton

## Blip tint per MeleeAttackPlan.TEMP_UPGRADE_CATALOG entry, same order
## (#406) — distinct from _blips' own blade-member fill_color (authored red
## on the scene) so the shared blade_size budget reads as one gauge with
## three legible kinds: blade members, Clamp spend, Spike spend.
const _UPGRADE_BLIP_COLORS: Array[Color] = [
	Color(0.4, 0.7, 0.95, 1),   # Clamp — cool metal-brace blue
	Color(0.95, 0.6, 0.25, 1),  # Spike — warm damage amber
]


func _on_bound() -> void:
	_swing_button.pressed.connect(_on_swing_pressed)
	_reset_button.pressed.connect(_battle_system.reset_plan)
	_launch_button.pressed.connect(_battle_system.launch_attack)
	_battle_system.attack_plan_state_changed.connect(_refresh)
	if _input_ctl != null:
		_input_ctl.player_can_act_changed.connect(_refresh.unbind(1))
		_input_ctl.temp_upgrade_arm_changed.connect(_refresh.unbind(1))
	_build_upgrade_buttons()
	_refresh()


func teardown() -> void:
	if _battle_system.attack_plan_state_changed.is_connected(_refresh):
		_battle_system.attack_plan_state_changed.disconnect(_refresh)
	if _input_ctl != null and _input_ctl.player_can_act_changed.is_connected(_refresh.unbind(1)):
		_input_ctl.player_can_act_changed.disconnect(_refresh.unbind(1))
	if _input_ctl != null and _input_ctl.temp_upgrade_arm_changed.is_connected(_refresh.unbind(1)):
		_input_ctl.temp_upgrade_arm_changed.disconnect(_refresh.unbind(1))


## One button per MeleeAttackPlan.TEMP_UPGRADE_CATALOG entry (#406) — a
## future catalog addition (e.g. the filed "edge sharpener") needs zero
## changes here. Labeled from the addon's authored `description`/tooltip
## title (SkillNodeAddon.get_tooltip_title), read off a throwaway instance
## since the catalog only carries scene/script references.
func _build_upgrade_buttons() -> void:
	for child in _upgrade_row.get_children():
		child.queue_free()
	for upgrade in MeleeAttackPlan.TEMP_UPGRADE_CATALOG:
		var tmp := (upgrade.scene as PackedScene).instantiate() as SkillNodeAddon
		var label := tmp.get_tooltip_title()
		tmp.free()
		var btn := Button.new()
		btn.text = label
		btn.toggle_mode = true
		btn.pressed.connect(_input_ctl.arm_temp_upgrade.bind(upgrade))
		_upgrade_row.add_child(btn)


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
	# Blips track the FULL shared budget (blade members + temp-upgrade spend,
	# #406), colored per kind: blade members keep the scene's authored red,
	# each temp-upgrade kind gets its own _UPGRADE_BLIP_COLORS tint, filled in
	# cost-many consecutive pips so e.g. a 2-cost Spike shows as 2 amber blips.
	var segment_colors: Array[Color] = []
	for _i in count:
		segment_colors.append(_blips.fill_color)
	if plan != null:
		for i in MeleeAttackPlan.TEMP_UPGRADE_CATALOG.size():
			var upgrade: Dictionary = MeleeAttackPlan.TEMP_UPGRADE_CATALOG[i]
			var spend := plan.temp_upgrade_cost_for(upgrade)
			for _j in spend:
				segment_colors.append(_UPGRADE_BLIP_COLORS[i])
	_blips.segment_colors = segment_colors
	_blips.count = segment_colors.size()
	_count_label.text = "pivot + %d" % count
	var cw: bool = _battle_system.next_melee_cw
	_swing_button.text = "↻ Swing CW" if cw else "↺ Swing CCW"
	var can_act := _input_ctl == null or _input_ctl.can_player_act()
	_launch_button.set_enabled(plan != null and plan.is_valid() and can_act)
	var arm: Variant = _input_ctl.temp_upgrade_arm() if _input_ctl != null else null
	for i in MeleeAttackPlan.TEMP_UPGRADE_CATALOG.size():
		var upgrade: Dictionary = MeleeAttackPlan.TEMP_UPGRADE_CATALOG[i]
		var btn := _upgrade_row.get_child(i) as Button
		btn.button_pressed = arm == upgrade
		btn.disabled = plan == null or not can_act or not plan.has_temp_upgrade_budget(upgrade)
