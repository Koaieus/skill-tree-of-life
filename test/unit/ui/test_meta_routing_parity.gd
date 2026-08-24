extends GutTest

## Characterization of the meta-menu routing **as `scenes/meta/meta_root.gd`
## ships it today**, written before #573 deletes [MenuStack] and [MenuScreen]
## (#568 acceptance 5).
##
## [b]This file is not here to describe a good design.[/b] It is here so that
## replacing the presentation cannot quietly change the routing. #573's whole
## acceptance is that this test stays green against the frontmatter panel layer,
## so it drives the SHIPPED screens by their button labels and records what
## comes out — including the parts that are awkward to reach, because awkward is
## exactly what gets lost silently in a rewrite.
##
## Three decisions live in `meta_root.gd` and nowhere else, and each has its own
## test below:
##
## 1. [code]_stamp_local_peer()[/code] — a HOST is peer 1 and knowable before any
##    socket opens; a CLIENT cannot know its own id and stays 0 for [GameRoot].
## 2. [code]_push_lobby()[/code] re-states the [NetworkConfig] role on EVERY
##    route including the offline ones, so a player who hosted, backed out and
##    then started a solo run does not silently open a socket.
## 3. START resolves [enum RunConfig.Mode] from the roster at press time (#554's
##    [method LobbyScreen.resolve_mode]), never from the button that was clicked.
##
## The second half of each route test asserts the SAME answer off
## [method MenuGraph.build] — that is the parity: the frontmatter's leaf data and
## the shipped screens agree today, so #573 can swap the screens out against a
## fixed target.

const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _META_ROOT := preload("res://scenes/meta/meta_root.tscn")
## The script, so the static `_stamp_local_peer()` can be called as a static.
const _META_SCRIPT := preload("res://scenes/meta/meta_root.gd")

var _meta: Control
var _tree: MenuGraph


func before_each() -> void:
	GameSession.network = null
	GameSession.local_peer_id = 0
	_tree = MenuGraph.build()
	_meta = _META_ROOT.instantiate()
	add_child_autofree(_meta)


func after_each() -> void:
	GameSession.network = null
	GameSession.local_peer_id = 0


# --- driving the shipped screens --------------------------------------------

## The splash is a sibling of the stack, not a scene of its own, and its
## `advanced` signal is what opens the main menu.
func _open_main_menu() -> MainMenuScreen:
	(_meta.get_node("%Splash") as SplashScreen).advanced.emit()
	return _top() as MainMenuScreen


func _stack() -> MenuStack:
	return _meta.get_node("%MenuStack") as MenuStack


## Top of the breadcrumb — [MenuStack] keeps ancestors alive, so the last child
## is the active screen. A popped screen is `queue_free`d and therefore still a
## child until the frame ends, which is why it is skipped rather than awaited
## away: backing out and pressing the next thing happens in one call here.
func _top() -> MenuScreen:
	var stack := _stack()
	for i in range(stack.get_child_count() - 1, -1, -1):
		var child := stack.get_child(i)
		if not child.is_queued_for_deletion():
			return child as MenuScreen
	fail_test("nothing is on the stack")
	return null


func _press(screen: MenuScreen, text: String) -> void:
	for child in screen.content.get_children():
		if child is Button and (child as Button).text == text:
			(child as Button).pressed.emit()
			return
	fail_test("no button labelled '%s' on %s" % [text, screen])


func _back(screen: MenuScreen) -> void:
	screen.back_button.pressed.emit()


func _humans(participants: Array[Participant]) -> Array[Participant]:
	var out: Array[Participant] = []
	for p in participants:
		if p.kind != Participant.Kind.AI:
			out.append(p)
	return out


## Walk down from whatever is on top, pressing one label per level.
func _descend(path: Array) -> MenuScreen:
	var screen := _top()
	for label in path:
		_press(screen, label)
		screen = _top()
	return screen


## Back out [param levels] screens, leaving the ancestor that opened them.
func _ascend(levels: int) -> void:
	for i in levels:
		_back(_top())


## Every route ends on the same lobby; only the [NetworkConfig] differs.
func _lobby_via(path: Array) -> LobbyScreen:
	_open_main_menu()
	return _descend(path) as LobbyScreen


# --- the four routes into a lobby -------------------------------------------

func test_new_game_is_offline_and_single() -> void:
	var lobby := _lobby_via(["Single Player", "New Game"])

	assert_eq(GameSession.network.role, NetworkTransport.Role.OFFLINE)
	assert_false(GameSession.network.is_online(), "a solo run opens no socket")
	assert_eq(lobby._mode, RunConfig.Mode.SINGLE, "the route asks for SINGLE")

	var cfg := lobby.build_run_config()
	assert_eq(cfg.mode, RunConfig.Mode.SINGLE)
	var humans := _humans(cfg.participants)
	assert_eq(humans.size(), 1)
	assert_eq(humans[0].camp, _PLAYER_FACTION)
	assert_eq(humans[0].peer_id, 0)

	var item := _tree.get_item(MenuGraph.ID_NEW_GAME)
	assert_eq(item.panel, MenuGraph.PANEL_LOBBY)
	assert_eq(item.route.requested_mode, lobby._mode)
	assert_eq(item.route.network_role, GameSession.network.role)


func test_hot_seat_is_offline_and_two_humans_on_one_camp() -> void:
	var lobby := _lobby_via(["Multiplayer", "Hot-Seat (this machine)"])

	assert_eq(GameSession.network.role, NetworkTransport.Role.OFFLINE)
	assert_eq(lobby._mode, RunConfig.Mode.COOP_HOTSEAT)

	var cfg := lobby.build_run_config()
	assert_eq(cfg.mode, RunConfig.Mode.COOP_HOTSEAT, "two humans sharing a camp is coop")
	var humans := _humans(cfg.participants)
	assert_eq(humans.size(), 2)
	assert_eq(humans[0].camp, _CAMP_1)
	assert_eq(humans[1].camp, _CAMP_1)

	var item := _tree.get_item(MenuGraph.ID_LOCAL)
	assert_eq(item.panel, MenuGraph.PANEL_LOBBY)
	assert_eq(item.route.requested_mode, lobby._mode)
	assert_eq(item.route.network_role, GameSession.network.role)


func test_host_listens_and_seats_the_absent_player_up_front() -> void:
	var screen := _open_main_menu() as MenuScreen
	_press(screen, "Multiplayer")
	var host_join := _top() as HostJoinScreen
	host_join._port_edit.text = "7777"
	_press(host_join, "Host")
	var lobby := _top() as LobbyScreen

	assert_eq(GameSession.network.role, NetworkTransport.Role.HOST)
	assert_eq(GameSession.network.port, 7777, "the typed port reaches the config")
	assert_true(GameSession.network.is_online())

	var cfg := lobby.build_run_config()
	var humans := _humans(cfg.participants)
	assert_eq(humans.size(), 2, "the remote seat exists before anyone joins (#554 D2)")
	assert_eq(humans[0].peer_id, NetworkTransport.HOST_PEER_ID, "this machine hosts")
	assert_true(LobbyScreen.is_pending_remote(humans[1]), "the joiner's seat is waiting")

	var item := _tree.get_item(MenuGraph.ID_HOST)
	assert_eq(item.panel, MenuGraph.PANEL_LOBBY)
	assert_eq(item.route.requested_mode, lobby._mode)
	assert_eq(item.route.network_role, GameSession.network.role)


func test_join_dials_and_offers_no_ai_opponents() -> void:
	var screen := _open_main_menu() as MenuScreen
	_press(screen, "Multiplayer")
	var host_join := _top() as HostJoinScreen
	host_join._address_edit.text = "192.168.1.7"
	host_join._port_edit.text = "7777"
	_press(host_join, "Join")
	var lobby := _top() as LobbyScreen

	assert_eq(GameSession.network.role, NetworkTransport.Role.CLIENT)
	assert_eq(GameSession.network.address, "192.168.1.7")
	assert_eq(GameSession.network.port, 7777)

	var cfg := lobby.build_run_config()
	assert_eq(cfg.ai_opponent_count, 0,
			"a client's own roster is replaced by the host's, so it authors no AI")
	var humans := _humans(cfg.participants)
	assert_eq(humans.size(), 2)
	assert_eq(humans[1].peer_id, NetworkTransport.HOST_PEER_ID, "the other seat is the host")

	var item := _tree.get_item(MenuGraph.ID_JOIN)
	assert_eq(item.panel, MenuGraph.PANEL_JOIN, "JOIN asks for an address before a lobby")
	assert_eq(item.route.requested_mode, lobby._mode)
	assert_eq(item.route.network_role, GameSession.network.role)


# --- decision 3: START resolves the mode from the roster, not the button -----

func test_a_networked_route_asks_for_coop_and_resolves_to_versus() -> void:
	# The single clearest statement of #554 D3: the button that opened the lobby
	# said COOP_HOTSEAT, and the run comes out VERSUS, because by then the roster
	# spans two camps. Nothing about "which button" survives to START.
	var screen := _open_main_menu() as MenuScreen
	_press(screen, "Multiplayer")
	_press(_top(), "Host")
	var lobby := _top() as LobbyScreen

	assert_eq(lobby._mode, RunConfig.Mode.COOP_HOTSEAT, "the ROUTE asked for coop")
	var cfg := lobby.build_run_config()
	assert_eq(cfg.mode, RunConfig.Mode.VERSUS, "the ROSTER answers versus")

	var humans := _humans(cfg.participants)
	assert_eq(humans[0].camp, _CAMP_1)
	assert_eq(humans[1].camp, _CAMP_2, "two camps is what makes it versus")
	assert_eq(LobbyScreen.resolve_mode(cfg.participants), RunConfig.Mode.VERSUS)


func test_the_resolved_mode_ignores_how_many_ai_join() -> void:
	var lobby := _lobby_via(["Single Player", "New Game"])
	lobby._ai_count_spin.value = 4
	var cfg := lobby.build_run_config()
	assert_eq(cfg.ai_opponent_count, 4)
	assert_eq(cfg.mode, RunConfig.Mode.SINGLE, "AI opponents are not humans")


# --- decision 2: the role is re-stated on every route, offline ones included -

func test_backing_out_of_hosting_and_starting_solo_opens_no_socket() -> void:
	# The scenario `_push_lobby`'s comment names. If an offline route left the
	# role alone instead of re-stating it, this player would silently host.
	var screen := _open_main_menu() as MenuScreen
	_press(screen, "Multiplayer")
	_press(_top(), "Host")
	assert_eq(GameSession.network.role, NetworkTransport.Role.HOST)

	_back(_top())  # out of the lobby
	_back(_top())  # out of the host/join screen
	_press(_top(), "Single Player")
	_press(_top(), "New Game")

	assert_eq(GameSession.network.role, NetworkTransport.Role.OFFLINE)
	assert_false(GameSession.network.is_online(), "hosting did not survive the back-out")


func test_every_lobby_route_writes_a_network_config() -> void:
	# Not one of them leaves GameSession.network as it found it — that is the
	# invariant, stated over all four routes at once.
	_open_main_menu()
	for path in [
		["Single Player", "New Game"],
		["Multiplayer", "Hot-Seat (this machine)"],
		["Multiplayer", "Host"],
		["Multiplayer", "Join"],
	]:
		GameSession.network = null
		_descend(path)
		assert_not_null(GameSession.network, "%s states a role" % [path])
		_ascend(path.size())


# --- decision 1: which peer this machine is, before any socket opens ---------

func test_a_host_knows_its_own_peer_id_and_a_client_cannot() -> void:
	GameSession.network = NetworkConfig.host()
	_META_SCRIPT._stamp_local_peer()
	assert_eq(GameSession.local_peer_id, NetworkTransport.HOST_PEER_ID,
			"a host is always peer 1 under Godot's high-level multiplayer")

	GameSession.local_peer_id = 99
	GameSession.network = NetworkConfig.join("10.0.0.4")
	_META_SCRIPT._stamp_local_peer()
	assert_eq(GameSession.local_peer_id, 0,
			"a client's id is minted on connect — GameRoot stamps it from the transport")

	GameSession.local_peer_id = 99
	GameSession.network = NetworkConfig.offline()
	_META_SCRIPT._stamp_local_peer()
	assert_eq(GameSession.local_peer_id, 0, "offline is nobody in particular")

	GameSession.local_peer_id = 99
	GameSession.network = null
	_META_SCRIPT._stamp_local_peer()
	assert_eq(GameSession.local_peer_id, 0, "and an absent config is not a crash")


# --- the two leaves that never reach a lobby --------------------------------

func test_options_opens_the_settings_screen_and_touches_no_run_state() -> void:
	var main := _open_main_menu()
	_press(main, "Options")
	assert_true(_top() is OptionsMenuScreen)
	assert_null(GameSession.network, "opening options is not a route into a run")

	var item := _tree.get_item(MenuGraph.ID_OPTIONS)
	assert_eq(item.panel, MenuGraph.PANEL_SETTINGS)
	assert_null(item.route, "settings authors no run")


func test_quit_is_wired_to_exactly_one_thing() -> void:
	# Deliberately NOT pressed through `_meta`: meta_root connects this to
	# `get_tree().quit()`, which would end the test run. So the wiring is
	# asserted here and the signal itself on a standalone screen below.
	var main := _open_main_menu()
	assert_eq(main.quit_pressed.get_connections().size(), 1)

	var item := _tree.get_item(MenuGraph.ID_EXIT)
	assert_eq(item.panel, MenuGraph.PANEL_EXIT_CONFIRM,
			"the frontmatter asks first — #567's exit confirm is a panel, not a modal")
	assert_null(item.route)


func test_the_quit_option_emits_rather_than_quitting_by_itself() -> void:
	var standalone := MainMenuScreen.new()
	add_child_autofree(standalone)
	var fired: Array[int] = []
	standalone.quit_pressed.connect(func(): fired.append(1))
	_press(standalone, "Quit")
	assert_eq(fired.size(), 1, "the screen emits; meta_root decides that means quit")


# --- the tree is the routing, restated ---------------------------------------

func test_every_leaf_that_starts_a_run_names_a_network_role() -> void:
	# The offline ones state OFFLINE explicitly rather than leaving it unset —
	# same reason `_push_lobby` re-states it (decision 2), carried into the data.
	var routed := 0
	for id in _tree.ids():
		var item := _tree.get_item(id)
		if item.route == null:
			continue
		routed += 1
		assert_true(item.is_leaf(), "'%s' is a leaf" % id)
		assert_true(item.route.network_role in [
			NetworkTransport.Role.OFFLINE,
			NetworkTransport.Role.HOST,
			NetworkTransport.Role.CLIENT,
		], "'%s' names a role" % id)
	assert_eq(routed, 4, "new game, local, host, join — the four routes into a lobby")


func test_the_parked_load_screen_starts_nothing() -> void:
	var item := _tree.get_item(MenuGraph.ID_LOAD_GAME)
	assert_true(item.disabled, "#23 save/load is parked; today's screen disables it too")
	assert_null(item.route)
	assert_eq(item.panel, MenuGraph.PANEL_LOAD)
