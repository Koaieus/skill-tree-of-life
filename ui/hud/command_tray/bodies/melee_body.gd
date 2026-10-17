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
@onready var _quickbar_row: HBoxContainer = %Quickbar
@onready var _swap_fan: CardFan = %SwapFan
@onready var _swing_button: Button = %SwingButton
@onready var _reform_button: Button = %ReformButton
@onready var _reset_button: Button = %ResetButton
@onready var _launch_button: LaunchAttackButton = %LaunchButton
@onready var _fuse_scrubber: FuseScrubber = %FuseScrubber

## Blip tint per addon kind in the battle system's catalog — used for the
## upgrade-spend pips, the addon-outline decoration on blade-region pips and the
## card accent, so one colour means one addon kind everywhere in this panel.
## The colour is the addon scene's own authored [member SkillNodeAddon.tint]; the
## armed-mode badge reads the same field, so card and badge cannot drift apart.
static func _upgrade_color(scene: PackedScene) -> Color:
	return SkillNodeAddon.tint_of(scene)

## Force-hover refcounts, keyed by SkillNode — owned exclusively here, so the
## panel is the only thing that can leave a node forced-hovered. Cleared at the
## top of every _refresh() because a rebuilt grid frees the pip under the cursor
## without firing its mouse_exited (see CapacityBlips._teardown_children()).
##
## A COUNT rather than a single node (#718): a collapsed `◆ × N` chip hovers
## every node in its run at once, the same node can appear in both the blade and
## the spend grid, and a cost-2 upgrade binds its node to two spend pips. Any of
## those means "enter" can arrive twice for one node, and a plain set would let
## the first "exit" un-hover a node the cursor is still over.
var _hover_counts: Dictionary = {}


func _on_bound() -> void:
	_swing_button.pressed.connect(_on_swing_pressed)
	_reform_button.pressed.connect(_on_reform_pressed)
	_reset_button.pressed.connect(_reset_plan)
	_launch_button.pressed.connect(_on_launch_pressed)
	if _armed_stack != null:
		_armed_stack.attack_plan_state_changed.connect(_refresh)
	if _input_ctl != null:
		_input_ctl.player_can_act_changed.connect(_refresh.unbind(1))
		_input_ctl.temp_upgrade_arm_changed.connect(_refresh.unbind(1))
		# A card arms only on a Blade, which is pushed AFTER the pivot's
		# state_changed — the stack's own change is what re-reads it.
		if _input_ctl.armed_stack != null:
			_input_ctl.armed_stack.changed.connect(_refresh)
	_blade_blips.pip_clicked.connect(_on_pip_clicked)
	_blade_blips.pip_hover_changed.connect(_on_pip_hover_changed)
	_upgrade_blips.pip_hover_changed.connect(_on_pip_hover_changed)
	_fuse_scrubber.edited.connect(_refresh)
	_fuse_scrubber.marker_hovered.connect(_on_fuse_marker_hovered)
	_swap_fan.picked.connect(_on_swap_picked)
	_swap_fan.dismissed.connect(_close_swap_fan)
	_quickbar = _input_ctl.temp_quickbar() if _input_ctl != null else TempQuickbar.new()
	if not _quickbar.changed.is_connected(_on_quickbar_changed):
		_quickbar.changed.connect(_on_quickbar_changed)
	_build_upgrade_buttons()
	_refresh()


func teardown() -> void:
	if _armed_stack != null and _armed_stack.attack_plan_state_changed.is_connected(_refresh):
		_armed_stack.attack_plan_state_changed.disconnect(_refresh)
	if _input_ctl != null and _input_ctl.player_can_act_changed.is_connected(_refresh.unbind(1)):
		_input_ctl.player_can_act_changed.disconnect(_refresh.unbind(1))
	if _input_ctl != null and _input_ctl.temp_upgrade_arm_changed.is_connected(_refresh.unbind(1)):
		_input_ctl.temp_upgrade_arm_changed.disconnect(_refresh.unbind(1))
	if _input_ctl != null and _input_ctl.armed_stack != null \
			and _input_ctl.armed_stack.changed.is_connected(_refresh):
		_input_ctl.armed_stack.changed.disconnect(_refresh)
	if _blade_blips.pip_clicked.is_connected(_on_pip_clicked):
		_blade_blips.pip_clicked.disconnect(_on_pip_clicked)
	if _blade_blips.pip_hover_changed.is_connected(_on_pip_hover_changed):
		_blade_blips.pip_hover_changed.disconnect(_on_pip_hover_changed)
	if _upgrade_blips.pip_hover_changed.is_connected(_on_pip_hover_changed):
		_upgrade_blips.pip_hover_changed.disconnect(_on_pip_hover_changed)
	if _fuse_scrubber.edited.is_connected(_refresh):
		_fuse_scrubber.edited.disconnect(_refresh)
	if _fuse_scrubber.marker_hovered.is_connected(_on_fuse_marker_hovered):
		_fuse_scrubber.marker_hovered.disconnect(_on_fuse_marker_hovered)
	if _swap_fan.picked.is_connected(_on_swap_picked):
		_swap_fan.picked.disconnect(_on_swap_picked)
	if _swap_fan.dismissed.is_connected(_close_swap_fan):
		_swap_fan.dismissed.disconnect(_close_swap_fan)
	if _quickbar != null and _quickbar.changed.is_connected(_on_quickbar_changed):
		_quickbar.changed.disconnect(_on_quickbar_changed)
	_close_swap_fan()
	_push_fuse_stranded([] as Array[SkillNode])
	_clear_hover()


## Click-to-toggle on a blade-region pip (#406 follow-up) — same armed-upgrade
## gating as clicking the node itself in the graph; a no-op with nothing armed.
func _on_pip_clicked(node: SkillNode) -> void:
	if _input_ctl != null:
		_input_ctl.request_temp_upgrade_at(node)


func _on_pip_hover_changed(node: SkillNode, hovering: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	if hovering:
		var depth: int = int(_hover_counts.get(node, 0))
		_hover_counts[node] = depth + 1
		if depth == 0:
			node.set_forced_hover(true)
	elif _hover_counts.has(node):
		var depth: int = int(_hover_counts[node]) - 1
		if depth > 0:
			_hover_counts[node] = depth
		else:
			_hover_counts.erase(node)
			node.set_forced_hover(false)


## A fuse marker stands for its gate's edge: hovering it hovers both ends.
func _on_fuse_marker_hovered(gate: Gate, hovering: bool) -> void:
	if gate == null or not is_instance_valid(gate):
		return
	_on_pip_hover_changed(gate.from, hovering)
	_on_pip_hover_changed(gate.to, hovering)


## Drops EVERY forced hover this panel is holding. The invariant it exists to
## keep: after this (and therefore after every _refresh()), no node anywhere is
## left forced-hovered by the tray, however many pips were over it.
func _clear_hover() -> void:
	for node in _hover_counts:
		if is_instance_valid(node):
			(node as SkillNode).set_forced_hover(false)
	_hover_counts.clear()


## The tray card for one temp upgrade (#465). A real scene rather than the
## `Button.new()` this used to emit — **owner call 2026-08-29:** *"does
## button.new in code → definitely need a scene"*
## (`.claude/rules/scene-composition.md`).
const _UPGRADE_BUTTON := preload("res://ui/hud/command_tray/bodies/temp_upgrade_button.tscn")


## The player's Z–B favourites this row shows ([TempQuickbar]), from their
## seat memory; repainted on its [signal TempQuickbar.changed].
var _quickbar: TempQuickbar
## The slot the open swap picker replaces, or -1 while it is closed.
var _swap_slot := -1


## One fixed slot per arming key ([constant PlayerInputController.TEMP_UPGRADE_HOTKEYS])
## — the row never grows with the catalog. A filled slot is a card for its
## scene; an empty one a same-width placeholder. Cost comes off the scene;
## label and glyph off a throwaway instance of the addon's own scene (#465),
## the same authored [member SkillNodeAddon.icon] [TempUpgradeMode] puts on
## the cursor. Right-click on any slot opens the swap picker.
func _build_upgrade_buttons() -> void:
	for child in _quickbar_row.get_children():
		_quickbar_row.remove_child(child)
		child.queue_free()
	for i in _quickbar.slots.size():
		var upgrade := _quickbar.scene_at(i)
		var slot: Control
		if upgrade == null:
			slot = Control.new()
			slot.custom_minimum_size = Vector2(_SLOT_WIDTH, 0.0)
			slot.mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			var tmp := upgrade.instantiate() as SkillNodeAddon
			var btn := _UPGRADE_BUTTON.instantiate() as TempUpgradeButton
			btn.label_text = tmp.get_tooltip_title()
			btn.icon_texture = tmp.icon
			tmp.free()
			btn.keycap = PlayerInputController.temp_upgrade_keycap(i)
			btn.costs = SkillNodeAddon.temp_costs_of(upgrade)
			btn.accent = _upgrade_color(upgrade)
			if _input_ctl != null:
				btn.pressed.connect(_input_ctl.arm_temp_upgrade.bind(upgrade))
			slot = btn
		slot.gui_input.connect(_on_slot_gui_input.bind(i))
		_quickbar_row.add_child(slot)


## An empty slot's width: a [TempUpgradeButton]'s fixed card width.
const _SLOT_WIDTH := 128.0


func _on_quickbar_changed() -> void:
	_close_swap_fan()
	_build_upgrade_buttons()
	_refresh()


func _on_slot_gui_input(event: InputEvent, i: int) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()
		open_swap_picker(i)


## Opens the [CardFan] swap picker at slot [param i]: every kind the player
## could place ([method PlayerInputController.available_temp_kinds]), the
## slot's current one lit. A pick swaps it in and pins the slot.
func open_swap_picker(i: int) -> void:
	if _input_ctl == null or i < 0 or i >= _quickbar_row.get_child_count():
		return
	_swap_slot = i
	var current := _quickbar.scene_at(i)
	var lit: Array[PackedScene] = []
	if current != null:
		lit.append(current)
	_swap_fan.bind(_input_ctl.available_temp_kinds(), SkillNodeAddon.temp_costs_of, lit)
	var slot := _quickbar_row.get_child(i) as Control
	_swap_fan.global_position = slot.get_global_rect().get_center()
	_swap_fan.visible = true


## The open swap picker's slot, or -1 while it is closed.
func swap_slot() -> int:
	return _swap_slot


func _on_swap_picked(scene: PackedScene) -> void:
	var i := _swap_slot
	_close_swap_fan()
	if i >= 0:
		_quickbar.swap(i, scene)


func _close_swap_fan() -> void:
	_swap_slot = -1
	if _swap_fan != null:
		_swap_fan.visible = false


## Rebuild the last launched blade (#466) — it does NOT launch, so the shape
## can still be re-aimed or carry a temp upgrade before it commits. The button
## is only ever enabled when this will succeed; the R keybind is the same call.
func _on_reform_pressed() -> void:
	if _input_ctl != null:
		_input_ctl.reform_blade()


func _on_swing_pressed() -> void:
	if _armed_stack == null:
		return
	var melee_memory := _armed_stack.memory_for(_player).melee
	melee_memory.next_swing_cw = not melee_memory.next_swing_cw
	var plan := _armed_plan() as MeleeAttackPlan
	if plan != null:
		plan.swing_cw = melee_memory.next_swing_cw
	_refresh()


func _refresh() -> void:
	_clear_hover()
	var plan := _armed_plan() as MeleeAttackPlan
	var max_blades := plan.max_blades() if plan != null else 1
	var count := plan.blade_nodes.size() if plan != null else 0
	var temp_total := plan.temp_upgrade_cost_total() if plan != null else 0
	_hint.text = "Right-click a pivot, left-click to grow the blade up to %d connected nodes. The shape is copied and swung once." % max_blades

	# Blade-region grid: used (red, bound to blade_nodes[i]) then unused
	# (gray, unbound). Upgrade spend is a SEPARATE row below (#718) — the row
	# break is the separator now, so there is no divider rule to keep in step.
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

	# Upgrade-region grid: one pip per is_temporary addon's blade_size cost, colored and
	# bound per the node actually carrying it (also hoverable, per #406).
	var upgrade_bound: Array = []
	var upgrade_colors: Array[Color] = []
	if plan != null:
		var priced := plan.temp_prices()
		for upgrade in _battle_system.temp_upgrade_kinds():
			for entry in priced:
				var a := entry[0] as SkillNodeAddon
				if a.get_kind() == upgrade.resource_path:
					for _j in (entry[1] as Dictionary).get(&"blade_size", 0):
						upgrade_bound.append(a.get_parent() as SkillNode)
						upgrade_colors.append(_upgrade_color(upgrade))
	_upgrade_blips.max_count = upgrade_bound.size()
	_upgrade_blips.bound_nodes = upgrade_bound
	_upgrade_blips.segment_colors = upgrade_colors
	_upgrade_blips.count = upgrade_bound.size()

	_count_label.text = "pivot + %d" % count
	var cw: bool = _armed_stack != null and _armed_stack.memory_for(_player).melee.next_swing_cw
	_swing_button.text = "↻ Swing CW" if cw else "↺ Swing CCW"
	var can_act := _input_ctl == null or (_input_ctl.can_player_act() and _input_ctl.can_afford(plan))
	_launch_button.set_enabled(plan != null and plan.is_valid() and can_act)
	# Greys out rather than half-reforming (#466): can_reform() re-runs the
	# real selection gates against live territory, so a blade whose members
	# have been deallocated (or that no longer fits blade_size) simply reads
	# as unavailable. No extra signal drives this — _refresh already runs on
	# attack_plan_state_changed and player_can_act_changed, and the latter
	# fires whenever a command finishes applying, which covers the territory
	# changes that flip the answer.
	_reform_button.disabled = _input_ctl == null or not _input_ctl.can_reform()
	# Arm and affordability are pushed as two SEPARATE facts (#465), never
	# collapsed into `Button.disabled`: "out of blade budget", "not your turn"
	# and "not selected" are three different sentences and the card paints them
	# as three. Which of them wins visually is TempUpgradeButton.state's call.
	var arm: PackedScene = _input_ctl.temp_upgrade_arm() if _input_ctl != null else null
	for i in mini(_quickbar.slots.size(), _quickbar_row.get_child_count()):
		var upgrade := _quickbar.scene_at(i)
		var btn := _quickbar_row.get_child(i) as TempUpgradeButton
		if upgrade == null or btn == null:
			continue
		btn.armed = arm == upgrade
		# The card shows the NEXT one's price: it escalates with the plan.
		btn.costs = plan.next_temp_costs(upgrade) if plan != null \
				else SkillNodeAddon.temp_costs_of(upgrade)
		# No blade up reads as unavailable: a card arms "Only with a blade"
		# (owner, 2026-09-30).
		btn.affordable = plan != null and can_act and plan.has_temp_upgrade_budget(upgrade) \
				and (_input_ctl == null or _input_ctl.can_arm_temp_upgrade())

	_fuse_scrubber.sync(plan)
	# _clear_hover() above dropped the marker's hover with everything else.
	_on_fuse_marker_hovered(_fuse_scrubber.hovered_gate(), true)
	# Mid-write the plan is between gates; the scrubber's `edited` lands here
	# once the whole gesture step is in.
	if not _fuse_scrubber.is_editing():
		_refresh_fuse_warning(plan)


## The plan-time self-cut warning: the fused swing's predicted stranded union
## feeds the chip and the gate-cut highlight. Resolved whole, here, only while a
## fuse is armed — the warning must match what launching commits, and an
## unfused aim never pays for it (MeleePreview's sliced pump is untouched).
## [method MeleeAttackPlan.refresh_prediction] is idempotent per selection, so
## this and the preview's pump never resolve one selection twice.
func _refresh_fuse_warning(plan: MeleeAttackPlan) -> void:
	var stranded: Array[SkillNode] = []
	if plan != null and plan.is_valid() and not plan.gate_fuses().is_empty():
		plan.refresh_prediction()
		var p := plan.prediction()
		if p != null:
			stranded = p.predicted_stranded()
	_fuse_scrubber.show_stranded(stranded.size())
	_push_fuse_stranded(stranded)


func _push_fuse_stranded(stranded: Array[SkillNode]) -> void:
	if not is_inside_tree():
		return
	var hc := get_tree().get_first_node_in_group(HighlightController.GROUP) as HighlightController
	if hc != null:
		hc.fuse_stranded = stranded


## Outline colors (up to two, catalog order) for every catalog addon kind
## currently attached to `node` — permanent or temp both count, so the outline
## reflects what the node actually carries, not just player spend (that
## distinction is the separate manual-marker rectangle). Hence a bare KIND
## match (the addon's scene), with no [member SkillNodeAddon.is_temporary] test.
func _outline_colors_for(node: SkillNode) -> Array[Color]:
	var colors: Array[Color] = []
	for a in node.get_addons():
		for upgrade in _battle_system.temp_upgrade_kinds():
			if a.get_kind() == upgrade.resource_path:
				colors.append(_upgrade_color(upgrade))
	return colors


func _has_manual_upgrade(node: SkillNode) -> bool:
	for a in node.get_addons():
		if a.is_temporary:
			return true
	return false


func _on_launch_pressed() -> void:
	_battle_system.launch_attack(_armed_plan())
