@tool
class_name MeleeBody
extends CommandTrayBodyBase
## Melee tab content (#114): blade-builder hint w/ [CapacityBlips] pips,
## Swing CW/CCW toggle, Launch. Only ever bound while [BattleSystem]'s
## attack mode is MELEE, so [member CommandTrayBodyBase._battle_system]'s
## plan is a [MeleeAttackPlan] whenever this body exists.

@onready var _hint: Label = %Hint
@onready var _blade_blips: CapacityBlips = %BladeBlips
@onready var _upgrade_blips: CapacityBlips = %UpgradeBlips
@onready var _count_label: Label = %CountLabel
@onready var _upgrade_row: HBoxContainer = %UpgradeRow
@onready var _swing_button: Button = %SwingButton
@onready var _reset_button: Button = %ResetButton
@onready var _launch_button: LaunchAttackButton = %LaunchButton

## Blip tint per MeleeAttackPlan.TEMP_UPGRADE_CATALOG entry, same order
## (#406) — reused both for the upgrade-spend pips and as the addon-outline
## decoration on blade-region pips, so one color means one addon kind
## everywhere in this panel.
const _UPGRADE_BLIP_COLORS: Array[Color] = [
	Color(0.4, 0.7, 0.95, 1),   # Clamp — cool metal-brace blue
	Color(0.95, 0.6, 0.25, 1),  # Spike — warm damage amber
]

## The node a blip is currently forcing hover on, if any — owned exclusively
## here so at most one SkillNode is ever forced-hovered at a time. Cleared at
## the top of every _refresh() because a rebuilt grid frees the pip under the
## cursor without firing its mouse_exited (see CapacityBlips._rebuild()).
var _hovered_node: SkillNode = null


func _on_bound() -> void:
	_swing_button.pressed.connect(_on_swing_pressed)
	_reset_button.pressed.connect(_battle_system.reset_plan)
	_launch_button.pressed.connect(_battle_system.launch_attack)
	_battle_system.attack_plan_state_changed.connect(_refresh)
	if _input_ctl != null:
		_input_ctl.player_can_act_changed.connect(_refresh.unbind(1))
		_input_ctl.temp_upgrade_arm_changed.connect(_refresh.unbind(1))
	_blade_blips.pip_clicked.connect(_on_pip_clicked)
	_blade_blips.pip_hover_changed.connect(_on_pip_hover_changed)
	_upgrade_blips.pip_hover_changed.connect(_on_pip_hover_changed)
	_build_upgrade_buttons()
	_refresh()


func teardown() -> void:
	if _battle_system.attack_plan_state_changed.is_connected(_refresh):
		_battle_system.attack_plan_state_changed.disconnect(_refresh)
	if _input_ctl != null and _input_ctl.player_can_act_changed.is_connected(_refresh.unbind(1)):
		_input_ctl.player_can_act_changed.disconnect(_refresh.unbind(1))
	if _input_ctl != null and _input_ctl.temp_upgrade_arm_changed.is_connected(_refresh.unbind(1)):
		_input_ctl.temp_upgrade_arm_changed.disconnect(_refresh.unbind(1))
	if _blade_blips.pip_clicked.is_connected(_on_pip_clicked):
		_blade_blips.pip_clicked.disconnect(_on_pip_clicked)
	if _blade_blips.pip_hover_changed.is_connected(_on_pip_hover_changed):
		_blade_blips.pip_hover_changed.disconnect(_on_pip_hover_changed)
	if _upgrade_blips.pip_hover_changed.is_connected(_on_pip_hover_changed):
		_upgrade_blips.pip_hover_changed.disconnect(_on_pip_hover_changed)
	_clear_hover()


## Click-to-toggle on a blade-region pip (#406 follow-up) — same armed-upgrade
## gating as clicking the node itself in the graph; a no-op with nothing armed.
func _on_pip_clicked(node: SkillNode) -> void:
	if _input_ctl != null:
		_input_ctl.request_temp_upgrade_at(node)


func _on_pip_hover_changed(node: SkillNode, hovering: bool) -> void:
	if hovering:
		if _hovered_node != null and _hovered_node != node and is_instance_valid(_hovered_node):
			_hovered_node.set_forced_hover(false)
		_hovered_node = node
		node.set_forced_hover(true)
	elif _hovered_node == node:
		if is_instance_valid(node):
			node.set_forced_hover(false)
		_hovered_node = null


func _clear_hover() -> void:
	if _hovered_node != null and is_instance_valid(_hovered_node):
		_hovered_node.set_forced_hover(false)
	_hovered_node = null


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
	_clear_hover()
	var plan := _battle_system.attack_plan as MeleeAttackPlan
	var max_blades := plan.max_blades() if plan != null else 1
	var count := plan.blade_nodes.size() if plan != null else 0
	var temp_total := plan.temp_upgrade_cost_total() if plan != null else 0
	_hint.text = "Right-click a pivot, left-click to grow the blade up to %d connected nodes. The shape is copied and swung once." % max_blades

	# Blade-region grid: used (red, bound to blade_nodes[i]) then unused
	# (gray, unbound) — the ordering the ruler splits from upgrade spend.
	var blade_region_size: int = max(0, max_blades - temp_total)
	var blade_bound: Array = []
	var outline_a: Array[Color] = []
	var outline_b: Array[Color] = []
	var manual: Array[bool] = []
	for i in blade_region_size:
		if plan != null and i < count:
			var node: SkillNode = plan.blade_nodes[i]
			blade_bound.append(node)
			var colors := _outline_colors_for(node)
			outline_a.append(colors[0] if colors.size() > 0 else Color(0, 0, 0, 0))
			outline_b.append(colors[1] if colors.size() > 1 else Color(0, 0, 0, 0))
			manual.append(_has_manual_upgrade(node))
		else:
			blade_bound.append(null)
			outline_a.append(Color(0, 0, 0, 0))
			outline_b.append(Color(0, 0, 0, 0))
			manual.append(false)
	_blade_blips.max_count = blade_region_size
	_blade_blips.bound_nodes = blade_bound
	_blade_blips.outline_colors_a = outline_a
	_blade_blips.outline_colors_b = outline_b
	_blade_blips.manual_markers = manual
	_blade_blips.count = min(count, blade_region_size)

	# Upgrade-region grid: one pip per is_temporary addon's cost, colored and
	# bound per the node actually carrying it (also hoverable, per #406).
	var upgrade_bound: Array = []
	var upgrade_colors: Array[Color] = []
	if plan != null:
		var nodes: Array[SkillNode] = []
		if plan.source != null:
			nodes.append(plan.source)
		nodes.append_array(plan.blade_nodes)
		for i in MeleeAttackPlan.TEMP_UPGRADE_CATALOG.size():
			var upgrade: Dictionary = MeleeAttackPlan.TEMP_UPGRADE_CATALOG[i]
			for node in nodes:
				for a in node.get_addons():
					if a.is_temporary and a.get_script() == upgrade.script:
						for _j in a.temp_upgrade_cost:
							upgrade_bound.append(node)
							upgrade_colors.append(_UPGRADE_BLIP_COLORS[i])
	_upgrade_blips.max_count = upgrade_bound.size()
	_upgrade_blips.bound_nodes = upgrade_bound
	_upgrade_blips.segment_colors = upgrade_colors
	_upgrade_blips.count = upgrade_bound.size()

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


## Outline colors (up to two, catalog order) for every TEMP_UPGRADE_CATALOG
## addon kind currently attached to `node` — permanent or temp both count, so
## the outline reflects what the node actually carries, not just player spend
## (that distinction is the separate manual-marker rectangle).
func _outline_colors_for(node: SkillNode) -> Array[Color]:
	var colors: Array[Color] = []
	for a in node.get_addons():
		for i in MeleeAttackPlan.TEMP_UPGRADE_CATALOG.size():
			if a.get_script() == MeleeAttackPlan.TEMP_UPGRADE_CATALOG[i].script:
				colors.append(_UPGRADE_BLIP_COLORS[i])
	return colors


func _has_manual_upgrade(node: SkillNode) -> bool:
	for a in node.get_addons():
		if a.is_temporary:
			return true
	return false
