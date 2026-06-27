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
@onready var spell_picker_bar: SpellPickerBar = %SpellPickerBar
@onready var action_cluster: HBoxContainer = %ActionCluster
@onready var initiative_bar: InitiativeBar = %InitiativeBar
@onready var context_panel: ContextPanel = %ContextPanel

var _player: Entity
var _input_ctl: PlayerInputController
var _battle_system: BattleSystem
var _turn_manager: TurnManager
var _vision_system: VisionSystem

# Cluster extras — built once in compose() and parented into ActionCluster
# alongside the scene-authored LaunchAttackButton. CW/CCW shows only for
# melee; Reset shows for any active plan.
var _swing_dir_button: Button = null
var _reset_button: Button = null


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
	_vision_system = game_root.vision_system

	stats_panel.board = _player.stat_board
	stat_board_overlay.board = _player.stat_board

	# Contextual right-hand panel: swaps a pre-authored body per current context
	# (attack plan / core-move / pinned node / idle). It self-resolves off the
	# systems' signals; we just hand it the references.
	context_panel.bind(_turn_manager, _battle_system, _input_ctl, _player)

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
	end_turn_button.confirmed.connect(_end_turn)
	end_turn_button.text = "End Turn"

	_turn_manager.turn_started.connect(_on_turn_started)
	_turn_manager.turn_ended.connect(_on_turn_ended)
	_refresh_end_turn_button()

	# Banner routing — see ui_root.gd history before the refactor for the full
	# emit-order notes. Player-only: AI turns animate silently.
	_player.leveled_up.connect(_on_player_leveled_up)
	banner_layer.bind_turn_manager(_turn_manager)

	_install_cluster_extras()

	spell_picker_bar.bind_spellbook(_player.spellbook)
	spell_picker_bar.spell_selected.connect(_on_spell_selected)
	_battle_system.selected_spell_changed.connect(spell_picker_bar.sync_selected)
	if _player.spellbook != null and not _player.spellbook.spells.is_empty():
		_battle_system.selected_spell = _player.spellbook.spells[0]
	_refresh_spell_picker_visibility()

	# Initiative bar tracks the player's initiative pool. current_changed drives
	# the climb; replenished latches the ready/full state. Drain happens in
	# _on_turn_started when it's the player's turn.
	var init_pool := _player.stat_board.initiative if _player.stat_board != null else null
	if init_pool != null:
		initiative_bar.max_initiative = float(init_pool.value)
		init_pool.current_changed.connect(initiative_bar._on_initiative_changed)
		init_pool.replenished.connect(initiative_bar._on_ready)
		initiative_bar._on_initiative_changed(float(init_pool.current))  # initial sync

func _on_attack_plan_changed(plan: AttackPlan) -> void:
	var mode := plan.mode if plan else BattleSystem.AttackMode.NONE
	attack_mode_bar.set_active_mode(mode)
	_refresh_action_cluster()
	_refresh_launch_button()
	_refresh_spell_picker_visibility()
	_refresh_spell_picker_gating()


## Builds the CW/CCW + Reset buttons inside the scene-authored ActionCluster,
## sitting next to LaunchAttackButton. Per-button visibility is driven by
## [_refresh_action_cluster] — CW/CCW only on melee, Reset on any plan.
func _install_cluster_extras() -> void:
	if action_cluster == null:
		return
	_swing_dir_button = Button.new()
	_swing_dir_button.name = "SwingDirButton"
	_swing_dir_button.focus_mode = Control.FOCUS_NONE
	_swing_dir_button.custom_minimum_size = Vector2(72, 56)
	_swing_dir_button.pressed.connect(_on_swing_dir_pressed)
	action_cluster.add_child(_swing_dir_button)

	_reset_button = Button.new()
	_reset_button.name = "ResetButton"
	_reset_button.focus_mode = Control.FOCUS_NONE
	_reset_button.custom_minimum_size = Vector2(72, 56)
	_reset_button.text = "Reset"
	_reset_button.tooltip_text = "Clear targets for this attack (mode stays)"
	_reset_button.pressed.connect(_on_reset_pressed)
	action_cluster.add_child(_reset_button)

	_refresh_action_cluster()


func _on_swing_dir_pressed() -> void:
	_battle_system.next_melee_cw = not _battle_system.next_melee_cw
	var plan := _battle_system.attack_plan as MeleeAttackPlan
	if plan != null:
		plan.swing_cw = _battle_system.next_melee_cw
	_refresh_action_cluster()


func _on_reset_pressed() -> void:
	if _battle_system != null:
		_battle_system.reset_plan()


func _refresh_action_cluster() -> void:
	if _battle_system == null:
		return
	var plan := _battle_system.attack_plan
	var has_plan := plan != null
	# LaunchAttack stays in the cluster but hides when there's no plan to
	# launch — the AttackModeBar already advertises "pick a mode."
	launch_attack_button.visible = has_plan
	if _reset_button != null:
		_reset_button.visible = has_plan
	if _swing_dir_button != null:
		var is_melee := plan is MeleeAttackPlan
		_swing_dir_button.visible = is_melee
		if is_melee:
			var cw: bool = _battle_system.next_melee_cw
			_swing_dir_button.text = "↻ CW" if cw else "↺ CCW"


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


func _on_turn_started(entity: Entity) -> void:
	if entity == _player:
		banner_layer.enqueue(BannerRequest.make_for_entity(
				"YOUR TURN", "", BannerRequest.Style.DEFAULT, entity))
		# Player's turn: slide the (full) initiative bar out of view.
		var init_pool := _player.stat_board.initiative if _player.stat_board != null else null
		if init_pool != null:
			initiative_bar._on_owner_turn_started(float(init_pool.current))
	# Fresh turn: clear any stale confirm bubble and reaffirm enabled state.
	end_turn_button.hide_confirm()
	_refresh_end_turn_button()


func _on_turn_ended(entity: Entity) -> void:
	if entity == _player:
		if _battle_system != null:
			_battle_system.cancel_attack()
		# Turn's over: slide the (now ~empty) initiative bar back into view.
		var init_pool := _player.stat_board.initiative if _player.stat_board != null else null
		if init_pool != null:
			initiative_bar._on_owner_turn_ended(float(init_pool.current))
	end_turn_button.hide_confirm()
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


## EndTurn click flow:
##   * If the bubble is already open, second click hides it (toggle off).
##   * Ctrl-click skips the bubble entirely — for players who already know
##     they're forfeiting action points.
##   * No warning → just end the turn.
##   * Warning + no ctrl → show the bubble; click the bubble to commit.
func _on_end_turn_pressed() -> void:
	if _turn_manager.current_entity == null:
		return
	if end_turn_button.is_confirm_open():
		end_turn_button.hide_confirm()
		return
	var ctrl_held := Input.is_key_pressed(KEY_CTRL)
	var warning := _unspent_warning()
	if ctrl_held or warning == "":
		_end_turn()
		return
	end_turn_button.show_confirm(warning)


func _end_turn() -> void:
	_turn_manager.end_turn()


## Returns a short noun phrase if the player is about to waste ACTION POINTS,
## else "". SP/DP/MP are at the player's discretion — only AP triggers a
## confirm, and only while there's still something worth spending it on (an
## enemy node the player can see). With no visible enemy there are no
## AP-costing actions left, so unspent AP is not a warning.
func _unspent_warning() -> String:
	if _player == null or _player.stat_board == null:
		return ""
	var ap: PoolStat = _player.stat_board.action_points
	if ap == null or ap.current <= 0:
		return ""
	if not _any_enemy_visible():
		return ""
	return "%d unspent action point%s" \
			% [int(ap.current), "" if int(ap.current) == 1 else "s"]


## True if any node owned by a hostile entity is currently visible to the
## player. Used to suppress the unspent-AP warning when no attack target
## exists.
func _any_enemy_visible() -> bool:
	if _vision_system == null or _player == null:
		return false
	var graph := _player.navigator.graph if _player.navigator != null else null
	if graph == null:
		return false
	for node in graph.get_skill_nodes():
		if node == null or node.owned_by == null:
			continue
		if node.owned_by.faction == _player.faction:
			continue
		if _vision_system.is_visible(node):
			return true
	return false
