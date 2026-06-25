extends Control
class_name UIRoot

## UI-side composer. Holds no system references of its own — receives them
## via [method compose], called by the level composer (GameRoot) once both
## subtrees are in the tree. Widgets stay dumb (intent up, setters down);
## UIRoot translates between them and the systems.

@onready var stats_panel: StatsPanel = %StatsPanel
@onready var stat_board_overlay: StatBoardOverlay = %StatBoardOverlay
@onready var attack_mode_bar: AttackModeBar = %AttackModeBar
@onready var launch_attack_button: LaunchAttackButton = %LaunchAttackButton
@onready var end_turn_button: EndTurnButton = %EndTurnButton
@onready var banner_layer: BannerLayer = %BannerLayer
@onready var phase_indicator: PhaseIndicator = %PhaseIndicator
@onready var phase_context_panel: PhaseContextPanel = %PhaseContextPanel
@onready var spell_picker_bar: SpellPickerBar = %SpellPickerBar

var _player: Entity
var _input_ctl: PlayerInputController
var _battle_system: BattleSystem
var _turn_manager: TurnManager

# Per-turn latch — if the player ticked "Don't ask again this turn" in the
# end-turn confirm dialog, skip the dialog for the rest of this turn. Reset
# in _on_turn_ended.
var _skip_end_turn_confirm: bool = false

# Small CW/CCW toggle parented to UIRoot. Visible only while a MeleeAttackPlan
# is active. Created lazily in compose() so this remains scene-light.
var _swing_dir_button: Button = null


## Injected by [GameRoot] once it and UIRoot are both in the tree. Reaches
## into nothing outside this subtree — all deps arrive here.
##
## Discipline: every `source.signal.connect(target)` is paired with an
## immediate call to `target` using the source's current value, so initial
## state mirrors live state. New widgets joining UIRoot follow the same shape.
func compose(game_root: GameRoot) -> void:
	_player = game_root.player
	_input_ctl = game_root.input_ctl
	_battle_system = game_root.battle_system
	_turn_manager = game_root.turn_manager

	stats_panel.board = _player.stat_board
	stat_board_overlay.board = _player.stat_board

	attack_mode_bar.attack_mode_requested.connect(_input_ctl.on_attack_mode_requested)

	_battle_system.attack_plan_changed.connect(_on_attack_plan_changed)
	_battle_system.attack_plan_state_changed.connect(_refresh_launch_button)
	_on_attack_plan_changed(_battle_system.attack_plan)

	launch_attack_button.pressed.connect(_battle_system.launch_attack)

	_input_ctl.player_can_act_changed.connect(attack_mode_bar.set_enabled)
	_input_ctl.player_can_act_changed.connect(spell_picker_bar.set_enabled)
	_input_ctl.player_can_act_changed.connect(_refresh_launch_button.unbind(1))
	attack_mode_bar.set_enabled(_input_ctl.can_player_act())
	spell_picker_bar.set_enabled(_input_ctl.can_player_act())

	end_turn_button.pressed.connect(_on_end_turn_pressed)
	_turn_manager.phase_changed.connect(_on_phase_changed)
	_on_phase_changed(_turn_manager.current_entity, _turn_manager.current_phase)

	# End-of-turn cleanup: cancel any stale attack plan and disable the
	# end-turn button until it's the player's turn again. The banner system
	# now carries the "your turn just ended" feedback role.
	_turn_manager.turn_started.connect(_on_turn_started)
	_turn_manager.turn_ended.connect(_on_turn_ended)
	_refresh_end_turn_button()

	# Banner routing — translate gameplay signals into BannerLayer.enqueue()
	# calls. Player-only by design: AI turns animate silently. Emit order at
	# the player's turn start (per TurnManager.start_turn → _on_turn_started
	# → phase_changed) is:
	#   turn_started → (XP replenish; may emit leveled_up) → phase_changed(CONTRACT)
	# We fold CONTRACT into the turn-start banner ("TURN STARTED /
	# CONTRACTION PHASE") via _on_turn_started below, and skip the standalone
	# CONTRACT phase banner in _on_phase_changed.
	# TODO: KILL / YOU DIED banners — needs an entity-death signal that
	# doesn't exist yet (no is_dead / died emit anywhere). Wire here once
	# BattleSystem (or Entity) gains one.
	_player.leveled_up.connect(_on_player_leveled_up)

	# Hand the banner layer the turn manager so it can drop stale phase
	# banners (e.g. when the player rapid-end-turns past CONTRACT before its
	# announcement gets to play).
	banner_layer.bind_turn_manager(_turn_manager)

	_install_swing_dir_button()

	# Phase-driven contextual widgets: both self-subscribe once handed refs.
	phase_indicator.bind(_turn_manager)
	phase_context_panel.bind(_turn_manager, _battle_system)

	# Spell picker. Bound to the player's spellbook; default-selects the first
	# known spell so MagicAttackPlans land armed rather than falling back to
	# the bundled spell. Picker emits its selection; we route to BattleSystem
	# which updates any live magic plan in place. Bar visibility tracks magic
	# mode and its castability gating tracks the plan's selected source.
	spell_picker_bar.bind_spellbook(_player.spellbook)
	spell_picker_bar.spell_selected.connect(_on_spell_selected)
	_battle_system.selected_spell_changed.connect(spell_picker_bar.sync_selected)
	if _player.spellbook != null and not _player.spellbook.spells.is_empty():
		_battle_system.selected_spell = _player.spellbook.spells[0]
	_refresh_spell_picker_visibility()


func _on_attack_plan_changed(plan: AttackPlan) -> void:
	var mode := plan.mode if plan else BattleSystem.AttackMode.NONE
	attack_mode_bar.set_active_mode(mode)
	_refresh_launch_button()
	_refresh_spell_picker_visibility()
	_refresh_spell_picker_gating()
	_refresh_swing_dir_button()


## Build a small "Swing: CCW/CW" toggle button anchored just below the
## launch-attack FAB. Visible only while a melee plan is active; clicking
## flips both the live plan and BattleSystem's sticky next_melee_cw.
func _install_swing_dir_button() -> void:
	if _swing_dir_button != null:
		return
	_swing_dir_button = Button.new()
	_swing_dir_button.name = "SwingDirButton"
	_swing_dir_button.focus_mode = Control.FOCUS_NONE
	_swing_dir_button.anchor_left = 0.5
	_swing_dir_button.anchor_top = 0.65
	_swing_dir_button.anchor_right = 0.5
	_swing_dir_button.anchor_bottom = 0.65
	_swing_dir_button.offset_left = -60.0
	_swing_dir_button.offset_top = 50.0
	_swing_dir_button.offset_right = 60.0
	_swing_dir_button.offset_bottom = 80.0
	_swing_dir_button.pressed.connect(_on_swing_dir_pressed)
	add_child(_swing_dir_button)
	_refresh_swing_dir_button()


func _on_swing_dir_pressed() -> void:
	_battle_system.next_melee_cw = not _battle_system.next_melee_cw
	var plan := _battle_system.attack_plan as MeleeAttackPlan
	if plan != null:
		plan.swing_cw = _battle_system.next_melee_cw
	_refresh_swing_dir_button()


func _refresh_swing_dir_button() -> void:
	if _swing_dir_button == null:
		return
	var melee := _battle_system != null and _battle_system.attack_plan is MeleeAttackPlan
	_swing_dir_button.visible = melee
	var cw: bool = _battle_system.next_melee_cw if _battle_system != null else false
	_swing_dir_button.text = "Swing: %s" % ("CW ↻" if cw else "CCW ↺")


func _refresh_spell_picker_visibility() -> void:
	if spell_picker_bar == null:
		return
	var plan := _battle_system.attack_plan if _battle_system != null else null
	spell_picker_bar.visible = plan is MagicAttackPlan


func _refresh_spell_picker_gating() -> void:
	if spell_picker_bar == null or _battle_system == null:
		return
	var plan := _battle_system.attack_plan
	if plan is MagicAttackPlan:
		var mp := plan as MagicAttackPlan
		spell_picker_bar.update_gating_context(mp.attacker, mp.source)
	else:
		spell_picker_bar.update_gating_context(null, null)


## Plan presence + validity gate the launch button. Subscribed to both plan
## swap (attack_plan_changed) and plan-internal mutation
## (attack_plan_state_changed) so target-selection ticks the button live.
func _refresh_launch_button() -> void:
	var plan := _battle_system.attack_plan
	var can_act := _input_ctl == null or _input_ctl.can_player_act()
	launch_attack_button.set_enabled(plan != null and plan.is_valid() and can_act)
	# Source picks on the magic plan don't change the plan instance — they
	# fire attack_plan_state_changed. Refresh picker gating off the same hook
	# so disabled-state tracks the live source.
	_refresh_spell_picker_gating()


func _on_phase_changed(entity: Entity, phase: TurnManager.Phase) -> void:
	end_turn_button.phase = float(phase)
	match phase:
		TurnManager.Phase.CONTRACT: end_turn_button.text = "End CONTRACT → EXPAND"
		TurnManager.Phase.EXPAND:   end_turn_button.text = "End EXPAND → BATTLE"
		TurnManager.Phase.BATTLE:   end_turn_button.text = "End Turn"
	# Defensive: every phase transition also reaffirms button enabled state.
	# turn_started is the canonical trigger, but if any rotation path ever
	# leaves the button stale, the next phase change recovers it.
	_refresh_end_turn_button()
	# Banner: only the player gets phase announcements, and CONTRACT is
	# folded into the turn-start banner so we don't double up.
	if entity == _player:
		match phase:
			TurnManager.Phase.EXPAND:
				banner_layer.enqueue(BannerRequest.make_for_phase(
						"EXPAND PHASE", "", BannerRequest.Style.PHASE,
						entity, TurnManager.Phase.EXPAND))
			TurnManager.Phase.BATTLE:
				banner_layer.enqueue(BannerRequest.make_for_phase(
						"BATTLE PHASE", "", BannerRequest.Style.PHASE,
						entity, TurnManager.Phase.BATTLE))


func _on_turn_started(entity: Entity) -> void:
	if entity == _player:
		banner_layer.enqueue(BannerRequest.make_for_phase(
				"TURN STARTED", "CONTRACTION PHASE", BannerRequest.Style.DEFAULT,
				entity, TurnManager.Phase.CONTRACT))
	_refresh_end_turn_button()


func _on_turn_ended(entity: Entity) -> void:
	if entity == _player and _battle_system != null:
		# Stale plan would outlive the turn; cancelling clears the launch
		# button via attack_plan_changed → _refresh_launch_button.
		_battle_system.cancel_attack()
		# End-of-turn resets the unspent-points warning: next turn re-prompts
		# even if the player checked "don't ask again" last time.
		_skip_end_turn_confirm = false
	_refresh_end_turn_button()


func _on_player_leveled_up(new_level: int) -> void:
	banner_layer.enqueue(BannerRequest.make(
			"LEVEL UP",
			"+1 Skill Point — Level %d" % new_level,
			BannerRequest.Style.LEVEL_UP))


func _refresh_end_turn_button() -> void:
	var e = _turn_manager.current_entity == _player
	end_turn_button.set_enabled(e)


func _on_spell_selected(spell: SpellDef) -> void:
	_battle_system.selected_spell = spell


## Stop spacebar from re-triggering the last-clicked button via ui_accept while
## leaving the LaunchAttackButton's ui_launch_attack shortcut intact. Releasing
## focus (rather than consuming the event) means ui_accept lands on no control,
## but Shortcut activation — which doesn't require focus — still fires.
func _shortcut_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_SPACE and event.pressed:
		get_viewport().gui_release_focus()


func _on_end_turn_pressed() -> void:
	if _turn_manager.current_entity == null:
		return
	if _skip_end_turn_confirm:
		_advance_or_end_turn()
		return
	var warning := _unspent_warning()
	if warning == "":
		_advance_or_end_turn()
		return
	_show_end_turn_confirm(warning)


func _advance_or_end_turn() -> void:
	if not _turn_manager.advance_phase():
		_turn_manager.end_turn()


## Returns a short noun phrase if the current entity has resources they're
## about to forfeit by ending the phase, else "".
func _unspent_warning() -> String:
	if _player == null or _player.stat_board == null:
		return ""
	match _turn_manager.current_phase:
		TurnManager.Phase.CONTRACT:
			var dp: PoolStat = _player.stat_board.deallocation_points
			if dp != null and dp.current > 0:
				return "%d unspent deallocation point%s" \
						% [int(dp.current), "" if int(dp.current) == 1 else "s"]
		TurnManager.Phase.EXPAND:
			var sp: PoolStat = _player.stat_board.skill_points
			if sp != null and sp.current > 0:
				return "%d unspent skill point%s" \
						% [int(sp.current), "" if int(sp.current) == 1 else "s"]
		TurnManager.Phase.BATTLE:
			var ap: PoolStat = _player.stat_board.action_points
			if ap != null and ap.current > 0:
				return "%d unspent action point%s" \
						% [int(ap.current), "" if int(ap.current) == 1 else "s"]
	return ""


func _show_end_turn_confirm(warning: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "You still have %s. End anyway?" % warning
	dlg.ok_button_text = "End"
	dlg.cancel_button_text = "Cancel"
	var checkbox := CheckBox.new()
	checkbox.text = "Don't ask again this turn"
	dlg.add_child(checkbox)
	add_child(dlg)
	dlg.confirmed.connect(func() -> void:
		if checkbox.button_pressed:
			_skip_end_turn_confirm = true
		_advance_or_end_turn()
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()
