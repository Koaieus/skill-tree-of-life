@tool
class_name ActionCluster
extends Control
## Bottom-right cluster (#115, absorbs #90): Action Points [PoolGauge]
## (segmented) + an unspent-AP warning label, above the existing
## [EndTurnButton] reused as-is (it already carries its own shader-driven
## chunky/gold-seal look — see ui/end_turn_button/, nothing to restyle).
##
## Root stays a plain Control; HudRoot's APEndTurnSlot positions this with
## a fixed bottom-right anchor (not inside a Container), so no min-size
## forwarding is needed here (see attributes_panel.gd for that pattern
## where one IS needed).

@onready var _ap_gauge: PoolGauge = %APGauge
@onready var _value_label: Label = %ValueLabel
@onready var _warning_label: Label = %WarningLabel
@onready var _end_turn_button: EndTurnButton = %EndTurnButton

var _player: Entity
var _turn_manager: TurnManager
var _input_ctl: PlayerInputController
var _vision_system: VisionSystem


func bind(player: Entity, turn_manager: TurnManager, input_ctl: PlayerInputController, vision_system: VisionSystem) -> void:
	_player = player
	_turn_manager = turn_manager
	_input_ctl = input_ctl
	_vision_system = vision_system
	if _player == null or _player.stat_board == null:
		return

	var ap: PoolStat = _player.stat_board.action_points
	if ap != null:
		_ap_gauge.min_value = 0.0
		var sync := func():
			_ap_gauge.max_value = float(ap.value)
			_ap_gauge.cell_count = float(ap.value)
			_ap_gauge.current = float(ap.current)
			if _value_label != null:
				_value_label.text = "%d/%d" % [int(ap.current), int(ap.value)]
			_refresh_warning()
		ap.current_changed.connect(sync.unbind(1))
		ap.value_changed.connect(sync)
		sync.call()

	_end_turn_button.text = "End Turn"
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	_end_turn_button.confirmed.connect(_end_turn)

	if _input_ctl != null:
		_input_ctl.player_can_act_changed.connect(_refresh_end_turn_button.unbind(1))
	if _turn_manager != null:
		_turn_manager.turn_started.connect(_on_turn_started)
		_turn_manager.turn_ended.connect(_on_turn_ended)
	_refresh_end_turn_button()


func _on_turn_started(entity: Entity) -> void:
	if entity != _player:
		return
	_end_turn_button.hide_confirm()
	_refresh_end_turn_button()
	_refresh_warning()


func _on_turn_ended(entity: Entity) -> void:
	if entity != _player:
		return
	_end_turn_button.hide_confirm()
	_refresh_end_turn_button()


func _refresh_end_turn_button() -> void:
	if _turn_manager == null or _end_turn_button == null:
		return
	_end_turn_button.set_enabled(_turn_manager.current_entity == _player)


## Same shape as the pre-existing UIRoot._unspent_warning (kept in sync
## deliberately, not extracted — see #118 Cutover for the dedupe point once
## UIRoot retires): only AP triggers the confirm/warning, and only while
## there's still a visible enemy node worth spending it on.
##
## Fades via alpha rather than `.visible` — toggling `.visible` on a
## VBoxContainer child collapses its layout slot, which shoves EndTurnButton
## up/down every time the warning appears/disappears. Alpha keeps the slot
## (and everything below it) fixed in place.
func _refresh_warning() -> void:
	if _warning_label == null or _player == null or _player.stat_board == null:
		return
	var ap: PoolStat = _player.stat_board.action_points
	if ap == null or ap.current <= 0 or not _any_enemy_visible():
		_warning_label.modulate.a = 0.0
		return
	_warning_label.modulate.a = 1.0
	_warning_label.text = "%d unspent Action Point%s" % [int(ap.current), "" if int(ap.current) == 1 else "s"]


func _warning_showing() -> bool:
	return _warning_label != null and _warning_label.modulate.a > 0.5


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


func _on_end_turn_pressed() -> void:
	if _turn_manager == null or _turn_manager.current_entity == null:
		return
	if _end_turn_button.is_confirm_open():
		_end_turn_button.hide_confirm()
		return
	var ctrl_held := Input.is_key_pressed(KEY_CTRL)
	if ctrl_held or not _warning_showing():
		_end_turn()
		return
	_end_turn_button.show_confirm(_warning_label.text)


func _end_turn() -> void:
	if _turn_manager != null:
		_turn_manager.end_turn()
