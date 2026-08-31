extends GutTest

## Where the digits get typed: the HOST and JOIN config panels and the fields
## they share (#582, re-pointed from `test_host_join_screen.gd`).
##
## [b]These assertions are #531's, moved rather than rewritten.[/b] That issue's
## host/join screen was the only surface in the frontmatter that accepted a
## port, and this file was what kept "a typed port reaches the config" under
## test. #582 split that screen in two — [HostPanel] takes the port, [JoinPanel]
## takes address and port, and the shared parsing lives in [NetworkFields] — so
## every assertion below points at the new field rather than the deleted button.
## The end-to-end half of the same claim is
## `test_meta_routing_parity.gd::test_host_listens_...`.
##
## Same style as `test_lobby_roster.gd` — build the panel, read what it emits,
## skip the pixels. What these panels emit IS their whole contract.

const _HOST_PANEL := preload("res://ui/frontmatter/panels/host_panel.tscn")
const _JOIN_PANEL := preload("res://ui/frontmatter/panels/join_panel.tscn")

var _emitted: Array = []


func before_each() -> void:
	_emitted = []
	GameSession.network = null


func after_each() -> void:
	GameSession.network = null


func _host_panel() -> HostPanel:
	var panel: HostPanel = _HOST_PANEL.instantiate()
	add_child_autofree(panel)
	panel.host_requested.connect(func(port: int): _emitted.append(["host", port]))
	return panel


func _join_panel() -> JoinPanel:
	var panel: JoinPanel = _JOIN_PANEL.instantiate()
	add_child_autofree(panel)
	panel.join_requested.connect(
			func(address: String, port: int): _emitted.append(["join", address, port]))
	return panel


# --- the fields the panels are for -------------------------------------------

func test_host_emits_the_typed_port() -> void:
	var panel := _host_panel()
	panel.fields._port_edit.text = "7777"
	panel._host_button.pressed.emit()
	assert_eq(_emitted, [["host", 7777]])


func test_join_emits_the_typed_address_and_port() -> void:
	var panel := _join_panel()
	panel.fields._address_edit.text = "192.168.1.7"
	panel.fields._port_edit.text = "7777"
	panel._join_button.pressed.emit()
	assert_eq(_emitted, [["join", "192.168.1.7", 7777]])


func test_untouched_fields_carry_the_defaults() -> void:
	# 9099 is what the owner asked for as the default on BOTH panels (#582), and
	# it is the harness's port, so a dev typing nothing types the same number
	# everywhere. Nothing negotiates it.
	_host_panel()._host_button.pressed.emit()
	_join_panel()._join_button.pressed.emit()
	assert_eq(_emitted, [
		["host", NetworkConfig.DEFAULT_PORT],
		["join", NetworkConfig.DEFAULT_ADDRESS, NetworkConfig.DEFAULT_PORT],
	])


func test_a_blank_or_junk_field_falls_back_to_the_default() -> void:
	# A typo'd address should fail at the socket, with a message. An EMPTY one
	# should not dial "" — there is a sane default and no reason to punish it.
	var panel := _join_panel()
	panel.fields._address_edit.text = "   "
	panel.fields._port_edit.text = "not a port"
	panel._join_button.pressed.emit()
	assert_eq(_emitted, [["join", NetworkConfig.DEFAULT_ADDRESS, NetworkConfig.DEFAULT_PORT]])


func test_a_host_is_offered_no_address_to_dial() -> void:
	# A listener binds every interface rather than dialling one, which is why
	# `NetworkConfig.address` is documented as unread on a host. Where the host
	# can be REACHED is the lobby's readout, not a field on this panel.
	assert_false(_host_panel().fields._address_row.visible)
	assert_true(_join_panel().fields._address_row.visible)


func test_the_two_panels_share_one_answer_about_junk() -> void:
	# The reason [NetworkFields] exists: two copies of `_port()` would be two
	# answers to "what does junk in the box mean", and the port assertion above
	# would only pin one of them.
	var host := _host_panel()
	var join := _join_panel()
	host.fields._port_edit.text = "not a port"
	join.fields._port_edit.text = "not a port"
	assert_eq(host.fields.port(), join.fields.port())
	assert_eq(host.fields.port(), NetworkConfig.DEFAULT_PORT)


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
