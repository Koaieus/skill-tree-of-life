extends GutTest

## #531 — the type-an-IP screen, and the one thing it produces: a
## [NetworkConfig] on [GameSession] for the level to pick up.
##
## Same style as `test_lobby_roster.gd` — build the code-composed screen, read
## what it emits, and skip the pixels. The screen's job is small enough that
## "what did it emit" IS the whole contract.

var _emitted: Array = []


func before_each() -> void:
	_emitted = []
	GameSession.network = null


func after_each() -> void:
	GameSession.network = null


func _make_screen() -> HostJoinScreen:
	var screen := HostJoinScreen.new()
	add_child_autofree(screen)
	screen.host_pressed.connect(func(port: int): _emitted.append(["host", port]))
	screen.join_pressed.connect(
			func(address: String, port: int): _emitted.append(["join", address, port]))
	screen.hotseat_pressed.connect(func(): _emitted.append(["hotseat"]))
	return screen


## Buttons live in `content` in the order `add_option` was called, after the two
## field rows.
func _press(screen: HostJoinScreen, text: String) -> void:
	for child in screen.content.get_children():
		if child is Button and child.text == text:
			child.pressed.emit()
			return
	fail_test("no button labelled '%s'" % text)


func test_host_emits_the_typed_port() -> void:
	var screen := _make_screen()
	screen._port_edit.text = "7777"
	_press(screen, "Host")
	assert_eq(_emitted, [["host", 7777]])


func test_join_emits_the_typed_address_and_port() -> void:
	var screen := _make_screen()
	screen._address_edit.text = "192.168.1.7"
	screen._port_edit.text = "7777"
	_press(screen, "Join")
	assert_eq(_emitted, [["join", "192.168.1.7", 7777]])


func test_a_blank_or_junk_field_falls_back_to_the_default() -> void:
	# A typo'd address should fail at the socket, with a message. An EMPTY one
	# should not dial "" — there is a sane default and no reason to punish it.
	var screen := _make_screen()
	screen._address_edit.text = "   "
	screen._port_edit.text = "not a port"
	_press(screen, "Join")
	assert_eq(_emitted, [["join", NetworkConfig.DEFAULT_ADDRESS, NetworkConfig.DEFAULT_PORT]])


func test_hot_seat_is_still_reachable_from_this_screen() -> void:
	# The Multiplayer button used to go straight to a hot-seat lobby. #531 put a
	# screen in front of it; that must not be how hot-seat disappeared.
	var screen := _make_screen()
	_press(screen, "Hot-Seat (this machine)")
	assert_eq(_emitted, [["hotseat"]])


# --- what the level ends up reading -----------------------------------------

func test_a_join_config_carries_the_address_a_host_config_does_not() -> void:
	var joining := NetworkConfig.join("10.0.0.4", 7777)
	assert_eq(joining.role, NetworkTransport.Role.CLIENT)
	assert_eq(joining.address, "10.0.0.4")
	assert_true(joining.is_online())

	var hosting := NetworkConfig.host(7777)
	assert_eq(hosting.role, NetworkTransport.Role.HOST)
	assert_true(hosting.is_online())

	assert_false(NetworkConfig.offline().is_online(), "and offline is offline")


func test_ending_a_run_gives_the_wire_back() -> void:
	# A player who hosted, finished, and then starts a solo game must not
	# silently open a socket again.
	GameSession.network = NetworkConfig.host()
	GameSession.start(RunConfig.new())
	assert_true(GameSession.network.is_online(), "start() leaves the role alone")
	GameSession.end()
	assert_null(GameSession.network)
