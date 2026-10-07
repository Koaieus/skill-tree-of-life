@tool
class_name GatesMenu
extends VBoxContainer
## The bulk gate controls, docked above the minimap: a `Gates ▾` popover of the
## five [enum PlayerInputController.GateAction]s (item id = enum value) and the
## strand-confirm line that the popover and the G hotkey share. Gates flip from
## any attack mode without clearing it, so this lives outside the command
## tray's per-mode bodies, where every tab can see the confirm.
##
## A level with no gates hides the whole chip (fixed per level, so nothing
## shoves); otherwise the button fades via alpha when the player has no gate
## to toggle right now.

@onready var _button: MenuButton = %GatesButton
@onready var _confirm_label: Label = %GateConfirmLabel

var _input_ctl: PlayerInputController
var _turn_manager: TurnManager


## System-lifetime wiring. Everything read here is the controller's CURRENT
## player, so a hot-seat handover needs only [method refresh], never a rebind.
func bind(input_ctl: PlayerInputController, turn_manager: TurnManager) -> void:
	_input_ctl = input_ctl
	_turn_manager = turn_manager
	if _input_ctl != null:
		_input_ctl.player_can_act_changed.connect(refresh.unbind(1))
		_input_ctl.gate_locks_changed.connect(refresh)
		_input_ctl.gate_confirm_changed.connect(_on_gate_confirm_changed)
		_button.get_popup().id_pressed.connect(_on_action_picked)
	if _turn_manager != null:
		_turn_manager.turn_started.connect(refresh.unbind(1))
		_turn_manager.turn_ended.connect(refresh.unbind(1))
	refresh()


func refresh() -> void:
	if _input_ctl == null or _input_ctl.graph == null:
		visible = false
		return
	visible = not _input_ctl.graph.get_gates().is_empty()
	var usable := _input_ctl.player != null and _turn_manager != null \
			and _turn_manager.current_entity == _input_ctl.player \
			and not _input_ctl.toggleable_gates().is_empty()
	_button.modulate.a = 1.0 if usable else 0.35
	_button.disabled = not usable


## Same one-warning shape as End Turn's unspent-AP confirm: the first pick of a
## stranding action arms (this label says what it costs), the same pick again
## goes through. The arm itself lives on the input controller, so G and the
## popover share it.
func _on_gate_confirm_changed(stranded: Array[SkillNode]) -> void:
	var n := stranded.size()
	_confirm_label.modulate.a = 1.0 if n > 0 else 0.0
	_confirm_label.text = "Strands %d node%s: repeat to confirm" % [n, "" if n == 1 else "s"]


func _on_action_picked(id: int) -> void:
	if _input_ctl != null:
		_input_ctl.request_gate_action(id as PlayerInputController.GateAction)
