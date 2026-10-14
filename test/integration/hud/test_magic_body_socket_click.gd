extends GutTest

## The composed magic tray body, driven by a real mouse click through the
## viewport's GUI pipeline: an owned infusion socket opens the aspect wheel, a
## locked ghost opens nothing but says why, and a lone socket hangs on the
## vessel's rim rather than sitting inside the spell.

const _BODY_SCENE := preload("res://ui/hud/command_tray/bodies/magic_body.tscn")
const _VENOM: SpellDef = preload("res://attack/spell/defs/venom_burst.tres")
## Rect overlap a socket may share with the vessel slot: the fan's end sockets
## tuck into the slot's empty corners, never into the circle.
const _MAX_VESSEL_OVERLAP_PX := 10.0

var _host: SubViewport
var _body: MagicBody
var _ctl: PlayerInputController


func after_each() -> void:
	if is_instance_valid(_body) and _ctl != null:
		_body.teardown()
	_ctl = null


## A body in its own viewport (GUT's UI would swallow the click), bound to a
## caster of [param intelligence] holding [param poison] of poison and no other
## aspect, with magic armed on venom burst.
func _arm(intelligence: float, poison: float = 0.0) -> void:
	_host = SubViewport.new()
	_host.size = Vector2i(1000, 400)
	_host.handle_input_locally = true
	_host.gui_disable_input = false
	add_child_autofree(_host)
	_body = _BODY_SCENE.instantiate() as MagicBody
	_host.add_child(_body)
	var h := SpellTestHelper.new()
	var graph := h.make_graph([[0, 1]], self)
	var caster := h.make_entity(graph, "ATK", Color.RED)
	var board := caster.stat_board
	board.intelligence.base_value = intelligence
	for aspect in AspectRoster.shared().aspects:
		if aspect.stat != null and board.get_stat(aspect.stat.id) != null:
			board.get_stat(aspect.stat.id).base_value = 0.0
	board.facet(&"poison", StatDef.Role.ASPECT).base_value = poison
	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.start_turn(caster)
	var bs := BattleSystem.new()
	bs.turn_manager = tm
	bs.graph = graph
	add_child_autofree(bs)
	_ctl = PlayerInputController.new()
	_ctl.graph = graph
	_ctl.turn_manager = tm
	_ctl.battle_system = bs
	_ctl.player = caster
	add_child_autofree(_ctl)
	_body.bind(caster, bs, _ctl)
	_ctl.armed_stack.select_spell(caster, _VENOM)
	_ctl.arm_attack(BattleSystem.AttackMode.MAGIC)
	_body.position = Vector2(20, 20)
	_body.size = Vector2(930, _body.get_combined_minimum_size().y)
	await wait_frames(3)
	_body.size = Vector2(930, _body.get_combined_minimum_size().y)
	await wait_frames(2)


func _sockets() -> InfusionSockets:
	return _body.get_node("%InfusionSockets") as InfusionSockets


func _click(socket: InfusionSocket) -> void:
	var at := socket.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		_host.push_input(ev, true)
	await wait_frames(2)


func test_clicking_an_owned_socket_opens_a_wheel_with_wedges() -> void:
	await _arm(10.0, 3.0)
	var sockets := _sockets()
	assert_eq(sockets.socket_count(), 1, "guard: INT 10 owns one socket")
	assert_null(_ctl.armed_stack.find(InfusionPickMode), "guard: nothing open yet")
	await _click(sockets.socket(0))
	var open := _ctl.armed_stack.find(InfusionPickMode) as InfusionPickMode
	assert_not_null(open, "the click pushed an InfusionPickMode")
	if open != null:
		assert_eq(open.socket, 0)
	assert_true(sockets.wheel().visible, "the wheel is shown")
	assert_gt(sockets.wheel().entry_count(), 0, "and offers a wedge")


func test_clicking_an_owned_socket_holding_no_aspects_opens_nothing_and_says_why() -> void:
	await _arm(10.0)
	var socket := _sockets().socket(0)
	assert_eq(socket.state, InfusionSocket.State.EMPTY, "guard: an owned socket")
	await _click(socket)
	assert_null(_ctl.armed_stack.find(InfusionPickMode), "an empty wheel is never opened")
	assert_false(_sockets().wheel().visible, "so no wheel")
	assert_eq(socket.hint_text(), "no aspects held", "the socket says why")
	assert_gt(socket.label_alpha(), 0.0, "and the hint is flashing")


func test_a_mid_run_unlock_gives_a_working_socket() -> void:
	await _arm(5.0, 3.0)
	var sockets := _sockets()
	assert_eq(sockets.socket_count(), 0, "guard: only the ghost")
	_ctl.player.stat_board.intelligence.base_value = 10.0
	_ctl.armed_stack.attack_plan().state_changed.emit()
	await wait_frames(3)
	assert_eq(sockets.socket_count(), 1, "the unlock added a socket")
	await _click(sockets.socket(0))
	assert_not_null(_ctl.armed_stack.find(InfusionPickMode), "the new socket opens its chooser")
	assert_gt(sockets.wheel().entry_count(), 0)


func test_clicking_the_ghost_opens_nothing_and_says_why() -> void:
	await _arm(5.0)
	var sockets := _sockets()
	assert_eq(sockets.socket_count(), 0, "guard: INT 5 owns none")
	var ghost := sockets.socket(0)
	assert_not_null(ghost, "guard: the ghost is socket 0")
	if ghost == null:
		return
	assert_eq(ghost.state, InfusionSocket.State.LOCKED)
	watch_signals(ghost)
	watch_signals(sockets)
	await _click(ghost)
	assert_null(_ctl.armed_stack.find(InfusionPickMode), "a locked socket opens no chooser")
	assert_false(sockets.wheel().visible, "and no wheel")
	assert_signal_emitted(ghost, "locked_tapped", "the ghost reports the tap")
	assert_signal_emitted_with_parameters(sockets, "locked_tapped", ["INT 10"])
	assert_gt(ghost.label_alpha(), ghost.ghost_label_alpha, "the threshold label flashes above its resting alpha")


func test_a_lone_socket_hangs_on_the_vessel_rim() -> void:
	await _arm(5.0)
	var ghost := _sockets().socket(0)
	var vessel := _body.get_node("%VesselSlot") as Control
	var overlap := ghost.get_global_rect().intersection(vessel.get_global_rect())
	assert_lt(overlap.size.y, _MAX_VESSEL_OVERLAP_PX,
			"the lone socket's rect %s overlaps the vessel %s by %s" % [
			ghost.get_global_rect(), vessel.get_global_rect(), overlap.size.y])


func test_the_wheel_stays_inside_the_viewport_near_its_bottom_edge() -> void:
	await _arm(10.0, 3.0)
	var sockets := _sockets()
	var socket := sockets.socket(0)
	_body.position.y = _host.size.y - (socket.global_position.y - _body.global_position.y) - 20.0
	await wait_frames(2)
	var limit := Rect2(Vector2.ZERO, Vector2(_host.size))
	assert_false(limit.encloses(Rect2(socket.get_global_rect().get_center() - Vector2.ONE * 96.0,
			Vector2.ONE * 192.0)), "guard: a wheel centred on the socket would overflow")
	await _click(socket)
	assert_true(sockets.wheel().visible, "guard: the wheel opened")
	var rect := sockets.wheel().get_global_rect()
	assert_true(limit.encloses(rect), "the wheel %s is clamped into the viewport %s" % [rect, limit])
