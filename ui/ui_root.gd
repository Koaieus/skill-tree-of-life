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

var _player: Entity
var _input_ctl: PlayerInputController
var _battle_system: BattleSystem
var _turn_manager: TurnManager


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
	attack_mode_bar.set_enabled(_input_ctl.can_player_act())

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


func _on_attack_plan_changed(plan: AttackPlan) -> void:
	var mode := plan.mode if plan else BattleSystem.AttackMode.NONE
	attack_mode_bar.set_active_mode(mode)
	_refresh_launch_button()


## Plan presence + validity gate the launch button. Subscribed to both plan
## swap (attack_plan_changed) and plan-internal mutation
## (attack_plan_state_changed) so target-selection ticks the button live.
func _refresh_launch_button() -> void:
	var plan := _battle_system.attack_plan
	launch_attack_button.set_enabled(plan != null and plan.is_valid())


func _on_phase_changed(entity: Entity, phase: TurnManager.Phase) -> void:
	end_turn_button.phase = float(phase)
	match phase:
		TurnManager.Phase.CONTRACT: end_turn_button.text = "Expand"
		TurnManager.Phase.EXPAND:   end_turn_button.text = "Battle"
		TurnManager.Phase.BATTLE:   end_turn_button.text = "End Turn"
	# Banner: only the player gets phase announcements, and CONTRACT is
	# folded into the turn-start banner so we don't double up.
	if entity == _player:
		match phase:
			TurnManager.Phase.EXPAND:
				banner_layer.enqueue(BannerRequest.make(
						"EXPAND PHASE", "", BannerRequest.Style.PHASE))
			TurnManager.Phase.BATTLE:
				banner_layer.enqueue(BannerRequest.make(
						"BATTLE PHASE", "", BannerRequest.Style.PHASE))


func _on_turn_started(entity: Entity) -> void:
	if entity == _player:
		banner_layer.enqueue(BannerRequest.make(
				"TURN STARTED", "CONTRACTION PHASE", BannerRequest.Style.DEFAULT))
	_refresh_end_turn_button()


func _on_turn_ended(entity: Entity) -> void:
	if entity == _player and _battle_system != null:
		# Stale plan would outlive the turn; cancelling clears the launch
		# button via attack_plan_changed → _refresh_launch_button.
		_battle_system.cancel_attack()
	_refresh_end_turn_button()


func _on_player_leveled_up(new_level: int) -> void:
	banner_layer.enqueue(BannerRequest.make(
			"LEVEL UP",
			"+1 Skill Point — Level %d" % new_level,
			BannerRequest.Style.LEVEL_UP))


func _refresh_end_turn_button() -> void:
	end_turn_button.set_enabled(_turn_manager.current_entity == _player)


func _on_end_turn_pressed() -> void:
	if _turn_manager.current_entity == null:
		return
	if not _turn_manager.advance_phase():
		_turn_manager.end_turn()
