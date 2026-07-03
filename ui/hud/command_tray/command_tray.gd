@tool
class_name CommandTray
extends VBoxContainer
## Bottom-center command tray shell (#113): mode tabs above a content area.
##
## Per the issue's own instruction, this reuses [AttackModeBar] (mode tabs)
## and [ContextPanel] (its existing body-swap pattern — idle/attack-plan/
## core-move/pinned-node bodies) verbatim rather than building a fresh
## Cinzel-tab visual or a second content-swapper; the wiring below mirrors
## [UIRoot.compose]'s wiring for the same two widgets.
##
## #114 (bespoke Manage/Melee/Ranged/Magic body scenes with CapacityBlips
## degree/pip displays) is NOT done here — ContextPanel's stock bodies are
## reused as-is for now. That's the next increment once this shell is
## proven; swapping ContextPanel's body scenes later doesn't touch this file.

@onready var attack_mode_bar: AttackModeBar = %AttackModeBar
@onready var context_panel: ContextPanel = %ContextPanel

var _input_ctl: PlayerInputController
var _battle_system: BattleSystem


func bind(turn_manager: TurnManager, battle_system: BattleSystem, input_ctl: PlayerInputController, player: Entity) -> void:
	_input_ctl = input_ctl
	_battle_system = battle_system

	context_panel.bind(turn_manager, battle_system, input_ctl, player)

	attack_mode_bar.attack_mode_requested.connect(input_ctl.on_attack_mode_requested)
	if _battle_system != null:
		_battle_system.attack_plan_changed.connect(_on_attack_plan_changed)
		_on_attack_plan_changed(_battle_system.attack_plan)

	if input_ctl != null:
		input_ctl.player_can_act_changed.connect(attack_mode_bar.set_enabled)
		attack_mode_bar.set_enabled(input_ctl.can_player_act())


func _on_attack_plan_changed(plan: AttackPlan) -> void:
	var mode := plan.mode if plan != null else BattleSystem.AttackMode.NONE
	attack_mode_bar.set_active_mode(mode)
