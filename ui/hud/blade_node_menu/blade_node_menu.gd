class_name BladeNodeMenu
extends Control

## The HUD face of [BladeNodeMenuMode]: a [CardFan] at the menu's node, shown
## whenever the armed stack's top is that mode. The un-pick hub sits under the
## cursor (the node that was clicked), so a second click un-picks. Every card
## is a temp kind placeable on that node right now, in the catalog's order
## ([method BladeNodeMenuMode.placeable]); a carried kind draws lit.
##
## Open: hold the [TooltipFan] down, bind the fan, then nudge the camera so the
## whole fan is on screen ([method GraphCamera.reveal], NUDGE) and show it on
## [signal GraphCamera.reveal_settled]. With no camera it shows at once. Close
## — on any pop of the mode, on camera input, on a left-click outside the fan
## (which falls through to the board), on the fan's [signal CardFan.dismissed].
## This node only reads the stack; every close it starts is the mode's pop.

@onready var _fan: CardFan = %CardFan

var _ctl: PlayerInputController
var _tooltip_fan: TooltipFan
var _camera: GraphCamera
## The mode the fan shows, or null while closed.
var _mode: BladeNodeMenuMode


func _ready() -> void:
	_fan.visible = false
	_fan.picked.connect(_on_picked)
	_fan.hub_pressed.connect(_on_hub_pressed)
	_fan.dismissed.connect(_close_mode)


func bind(input_ctl: PlayerInputController, tooltip_fan: TooltipFan, camera: GraphCamera) -> void:
	if _ctl != null and _ctl.armed_stack != null and _ctl.armed_stack.changed.is_connected(_sync):
		_ctl.armed_stack.changed.disconnect(_sync)
	_close()
	_ctl = input_ctl
	_tooltip_fan = tooltip_fan
	_camera = camera
	if _ctl != null and _ctl.armed_stack != null:
		_ctl.armed_stack.changed.connect(_sync)
	_sync()


## Whether a menu is up (bound and showing, or waiting on its reveal).
func is_open() -> bool:
	return _mode != null


func fan() -> CardFan:
	return _fan


func _process(_delta: float) -> void:
	if _mode != null and _fan.visible and is_instance_valid(_mode.node):
		_fan.position = _anchor_of(_mode.node)


func _sync() -> void:
	var top := _ctl.armed_stack.top() if _ctl != null and _ctl.armed_stack != null else null
	var mode := top as BladeNodeMenuMode
	if mode == _mode:
		return
	_close()
	if mode != null:
		_open(mode)


func _open(mode: BladeNodeMenuMode) -> void:
	_mode = mode
	if _tooltip_fan != null:
		_tooltip_fan.held = true
	var offered: Array[PackedScene] = []
	if _ctl != null and _ctl.battle_system != null:
		offered = _ctl.battle_system.temp_upgrade_kinds()
	var entries := mode.placeable(offered)
	var p := mode.plan()
	var costs_of: Callable = p.next_temp_costs if p != null else SkillNodeAddon.temp_costs_of
	_fan.bind(entries, costs_of, mode.carried(entries))
	if _camera == null:
		_show()
		return
	_camera.manual_input_received.connect(_close_mode)
	_camera.reveal(_world_rect_of(mode.node), GraphCamera.RevealPolicy.NUDGE)
	await _camera.reveal_settled
	if _mode == mode:
		_show()


func _show() -> void:
	_fan.position = _anchor_of(_mode.node)
	_fan.visible = true


func _close() -> void:
	if _camera != null and _camera.manual_input_received.is_connected(_close_mode):
		_camera.manual_input_received.disconnect(_close_mode)
	_mode = null
	_fan.visible = false
	if _tooltip_fan != null:
		_tooltip_fan.held = false


## Pop the open mode; [method _sync] then closes the view.
func _close_mode() -> void:
	if _mode != null:
		_mode.pop_self()


func _on_picked(scene: PackedScene) -> void:
	if _mode != null:
		_mode.pick(scene)


func _on_hub_pressed() -> void:
	if _mode != null:
		_mode.unpick()


## A left press the fan's own controls did not take closes the menu, NOT
## consumed: the physics pick that follows reaches the blade as if no menu
## were up.
func _unhandled_input(event: InputEvent) -> void:
	if _mode == null:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_close_mode()


## [param node]'s centre in this control's space.
func _anchor_of(node: SkillNode) -> Vector2:
	var screen := node.get_global_transform_with_canvas().origin
	return get_global_transform_with_canvas().affine_inverse() * screen


## The fan's footprint around [param node], in world space: every bound card's
## and the hub's rect (screen pixels about the hub's centre), scaled by zoom.
func _world_rect_of(node: SkillNode) -> Rect2:
	var local := Rect2(_fan.get_node(^"%Hub").position, (_fan.get_node(^"%Hub") as Control).size)
	for card in _fan.cards():
		local = local.merge(Rect2(card.position, card.size))
	var to_world := 1.0 / _camera.zoom.x if _camera.zoom.x > 0.0 else 1.0
	return Rect2(node.global_position + local.position * to_world, local.size * to_world)
