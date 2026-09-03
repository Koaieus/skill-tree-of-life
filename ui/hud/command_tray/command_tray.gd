@tool
class_name CommandTray
extends VBoxContainer
## Bottom-center command tray shell (#113/#114): the Cinzel mode-tab bar sits
## above a fixed-height content chrome that swaps in one of four bespoke
## per-mode body scenes (Manage/Melee/Ranged/Magic), keyed off
## [BattleSystem]'s active attack mode via [signal BattleSystem.attack_plan_changed]
## — the same source [AttackModeBar]/[PlayerInputController] already drive.
##
## Deliberately NOT [ContextPanel]: that swapper's contexts (attack-plan
## active / core-move targeting / pinned node / idle) are a different axis
## from "which mode tab is selected" — picking the Melee tab doesn't mean an
## attack plan exists yet, and a pinned node has nothing to do with the tab
## bar. Wiring ContextPanel in here verbatim (an earlier pass) meant the
## tray showed IDLE/PINNED content instead of the mode-specific builder UI
## the design calls for. See [CommandTrayBodyBase]'s doc comment for the
## full reasoning; the four body scenes live in `ui/hud/command_tray/bodies/`.

const _MANAGE_BODY := preload("res://ui/hud/command_tray/bodies/manage_body.tscn")
const _MELEE_BODY := preload("res://ui/hud/command_tray/bodies/melee_body.tscn")
const _RANGED_BODY := preload("res://ui/hud/command_tray/bodies/ranged_body.tscn")
const _MAGIC_BODY := preload("res://ui/hud/command_tray/bodies/magic_body.tscn")

@onready var attack_mode_bar: AttackModeBar = %AttackModeBar
@onready var _body_slot: Control = %BodySlot

var _input_ctl: PlayerInputController
var _battle_system: BattleSystem
var _player: Entity
var _current_mode: int = -1
var _current_body: CommandTrayBodyBase = null


## System-lifetime wiring: the mode source and the act gate. Split from
## [method set_player] because both are facts about the level, not about whose
## turn it is — re-running them on a hot-seat handover (#459) would
## double-connect and request every mode change twice.
func bind(battle_system: BattleSystem, input_ctl: PlayerInputController) -> void:
	_input_ctl = input_ctl
	_battle_system = battle_system

	attack_mode_bar.attack_mode_requested.connect(_on_mode_requested)
	if _battle_system != null:
		_battle_system.attack_plan_changed.connect(_on_attack_plan_changed)
		_on_attack_plan_changed(_battle_system.attack_plan)

	if input_ctl != null:
		input_ctl.player_can_act_changed.connect(attack_mode_bar.set_enabled)
		attack_mode_bar.set_enabled(input_ctl.can_player_act())


## #464: a request `BattleSystem` silently drops — AP=0, or mid-swing
## (`is_launching` flips true with no signal of its own, so nothing disables
## the bar at the exact moment a swing starts) — never fires
## `attack_plan_changed`, so the bar's native click visual is left showing a
## mode that never armed. Re-assert against ground truth after EVERY request,
## accepted or not; a no-op when it was accepted, since `_on_attack_plan_changed`
## already ran off the signal by the time this line executes.
func _on_mode_requested(mode: BattleSystem.AttackMode) -> void:
	_input_ctl.on_attack_mode_requested(mode)
	if _battle_system != null:
		_on_attack_plan_changed(_battle_system.attack_plan)


## Re-point the tray at [param player]. The live body reads `_player` at bind
## time, so it is torn down and rebuilt through the existing swap path rather
## than re-`bind()`ed in place — [method CommandTrayBodyBase.bind] connects,
## and only `teardown()` undoes that.
func set_player(player: Entity) -> void:
	if _player == player:
		return
	_player = player
	if _current_mode < 0:
		return  # no body built yet — the first `_swap_body` will read `_player`
	if not is_inside_tree():
		# Teardown (HudRoot._exit_tree unbinds to null): a body added to a tree
		# that is going away never gets its `_ready`, so its `@onready` refs are
		# null when `bind` reaches them. Nothing to re-point to anyway.
		return
	var mode := _current_mode
	_current_mode = -1
	_swap_body(mode as BattleSystem.AttackMode)


func _on_attack_plan_changed(plan: AttackPlan) -> void:
	var mode := plan.mode if plan != null else BattleSystem.AttackMode.NONE
	attack_mode_bar.set_active_mode(mode)
	_swap_body(mode)


func _swap_body(mode: BattleSystem.AttackMode) -> void:
	if mode == _current_mode:
		return
	_current_mode = mode
	if _current_body != null:
		_current_body.teardown()
		_current_body.queue_free()
		_current_body = null
	for child in _body_slot.get_children():
		child.queue_free()
	var scene := _scene_for(mode)
	if scene == null or _body_slot == null:
		return
	var body: CommandTrayBodyBase = scene.instantiate()
	_body_slot.add_child(body)
	body.bind(_player, _battle_system, _input_ctl)
	_current_body = body


func _scene_for(mode: BattleSystem.AttackMode) -> PackedScene:
	match mode:
		BattleSystem.AttackMode.MELEE: return _MELEE_BODY
		BattleSystem.AttackMode.RANGED: return _RANGED_BODY
		BattleSystem.AttackMode.MAGIC: return _MAGIC_BODY
	return _MANAGE_BODY
