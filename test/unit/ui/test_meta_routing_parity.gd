extends GutTest

## Characterization of the meta-menu routing, **re-pointed at the frontmatter**
## by #579 after #573 replaced the presentation.
##
## [b]This file is not here to describe a good design.[/b] It is here so that
## replacing the presentation cannot quietly change the routing. It was written
## against the shipped `MenuStack` breadcrumb (C1, #568); the deletion of
## `MenuStack` and `MenuScreen` made that driver impossible, so the driver — and
## only the driver — was swapped for [FrontmatterRoot]'s navigation. **Every
## assertion it made about the routing it still makes**, which is the whole
## point of the split that produced #579: a characterization test is meant to be
## re-pointed at the replacement, never weakened to fit it.
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
##    [method LobbyScreen.resolve_mode]), never from the route that was taken.
##
## The second half of each route test asserts the SAME answer off
## [method MenuGraph.build] — that is the parity: the frontmatter's leaf data and
## the live routing agree.
##
## [b]Navigation is walked, not jumped.[/b] `_navigate_to` focuses every id on
## the path from the root down, which is what a player pressing through the tree
## does. Focusing a leaf directly would reach the same panel while testing none
## of the traversal — and traversal is the reason #579 waited for C3 rather than
## re-pointing this file the moment the panels existed.

const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _META_ROOT := preload("res://scenes/meta/meta_root.tscn")
## The script, so the static `_stamp_local_peer()` can be called as a static.
const _META_SCRIPT := preload("res://scenes/meta/meta_root.gd")

var _meta: Control
var _frontmatter: FrontmatterRoot
var _panels: FrontmatterPanels
var _tree: MenuGraph


func before_each() -> void:
	GameSession.network = null
	GameSession.local_peer_id = 0
	_tree = MenuGraph.build()
	_meta = _META_ROOT.instantiate()
	add_child_autofree(_meta)
	_frontmatter = _meta.get_node("%Frontmatter") as FrontmatterRoot
	var found := _frontmatter.find_children("*", "FrontmatterPanels", true, false)
	_panels = found[0] as FrontmatterPanels


func after_each() -> void:
	GameSession.network = null
	GameSession.local_peer_id = 0


# --- driving the frontmatter --------------------------------------------------

## The splash is a sibling of the frontmatter, not a scene of its own, and its
## `advanced` signal is what hands the stage to the menu graph.
func _open_menu() -> void:
	(_meta.get_node("%Splash") as SplashScreen).advanced.emit()


## Walk from the root down to [param id], focusing each step — the traversal a
## player performs. `instant` so the panel routes in this call rather than a
## tween's last frame; #570 makes `set_progress(1.0)` the settle point either
## way, so this is the same code path a real navigation ends on.
func _navigate_to(id: StringName) -> void:
	_open_menu()
	for step in _tree.path_to(id):
		_frontmatter.focus(step, true)


## Up one level, which is [method FrontmatterRoot.back] and nothing else — under
## a moving camera back is the same call as forward (#567), so there is no
## breadcrumb to pop.
func _back() -> void:
	_frontmatter.back()


func _back_out(levels: int) -> void:
	for i in levels:
		_back()


## The lobby currently mounted on the panel layer, or null before a route
## configured one.
func _lobby() -> LobbyScreen:
	return (_panels.get_panel(MenuGraph.PANEL_LOBBY) as LobbyPanel).screen


func _join_screen() -> HostJoinScreen:
	return (_panels.get_panel(MenuGraph.PANEL_JOIN) as JoinPanel).screen


func _press(screen: Node, text: String) -> void:
	for child in (screen.content as Control).get_children():
		if child is Button and (child as Button).text == text:
			(child as Button).pressed.emit()
			return
	fail_test("no button labelled '%s' on %s" % [text, screen])


func _humans(participants: Array[Participant]) -> Array[Participant]:
	var out: Array[Participant] = []
	for p in participants:
		if p.kind != Participant.Kind.AI:
			out.append(p)
	return out


func _ai(participants: Array[Participant]) -> Array[Participant]:
	var out: Array[Participant] = []
	for p in participants:
		if p.kind == Participant.Kind.AI:
			out.append(p)
	return out


## The two networked routes reach their lobby through #531's address screen,
## because that screen is the only place a PORT can be typed — a leaf's
## [MenuGraph.Route] names a role, not digits. Walking to JOIN and pressing
## through is therefore the real path, not a shortcut around one.
func _dial(button: String, address: String = "", port: String = "") -> LobbyScreen:
	_navigate_to(MenuGraph.ID_JOIN)
	if address != "":
		_join_screen()._address_edit.text = address
	if port != "":
		_join_screen()._port_edit.text = port
	_press(_join_screen(), button)
	return _lobby()


# --- the four routes into a lobby -------------------------------------------

func test_new_game_is_offline_and_single() -> void:
	_navigate_to(MenuGraph.ID_NEW_GAME)
	var lobby := _lobby()

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
	_navigate_to(MenuGraph.ID_LOCAL)
	var lobby := _lobby()

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
	var lobby := _dial("Host", "", "7777")

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
	var lobby := _dial("Join", "192.168.1.7", "7777")

	assert_eq(GameSession.network.role, NetworkTransport.Role.CLIENT)
	assert_eq(GameSession.network.address, "192.168.1.7")
	assert_eq(GameSession.network.port, 7777)

	var cfg := lobby.build_run_config()
	# #584 deleted `ai_opponent_count`: the count was always derivable from
	# `participants`, and a second field describing that list could disagree
	# with it. Asserted on the list itself, which is what actually reaches a level.
	assert_eq(_ai(cfg.participants).size(), 0,
			"a client's own roster is replaced by the host's, so it authors no AI")
	var humans := _humans(cfg.participants)
	assert_eq(humans.size(), 2)
	assert_eq(humans[1].peer_id, NetworkTransport.HOST_PEER_ID, "the other seat is the host")

	var item := _tree.get_item(MenuGraph.ID_JOIN)
	assert_eq(item.panel, MenuGraph.PANEL_JOIN, "JOIN asks for an address before a lobby")
	assert_eq(item.route.requested_mode, lobby._mode)
	assert_eq(item.route.network_role, GameSession.network.role)


# --- decision 3: START resolves the mode from the roster, not the route ------

func test_a_networked_route_asks_for_coop_and_resolves_to_versus() -> void:
	# The single clearest statement of #554 D3: the route that opened the lobby
	# said COOP_HOTSEAT, and the run comes out VERSUS, because by then the roster
	# spans two camps. Nothing about "which route" survives to START.
	var lobby := _dial("Host")

	assert_eq(lobby._mode, RunConfig.Mode.COOP_HOTSEAT, "the ROUTE asked for coop")
	var cfg := lobby.build_run_config()
	assert_eq(cfg.mode, RunConfig.Mode.VERSUS, "the ROSTER answers versus")

	var humans := _humans(cfg.participants)
	assert_eq(humans[0].camp, _CAMP_1)
	assert_eq(humans[1].camp, _CAMP_2, "two camps is what makes it versus")
	assert_eq(LobbyScreen.resolve_mode(cfg.participants), RunConfig.Mode.VERSUS)


func test_the_resolved_mode_ignores_how_many_ai_join() -> void:
	_navigate_to(MenuGraph.ID_NEW_GAME)
	var lobby := _lobby()
	lobby._ai_count_row.value = 4
	var cfg := lobby.build_run_config()
	assert_eq(_ai(cfg.participants).size(), 4,
			"the spinbox's four AI reach the run as four AI participants (#584)")
	assert_eq(cfg.mode, RunConfig.Mode.SINGLE, "AI opponents are not humans")


# --- decision 2: the role is re-stated on every route, offline ones included -

func test_backing_out_of_hosting_and_starting_solo_opens_no_socket() -> void:
	# The scenario `_push_lobby`'s comment names. If an offline route left the
	# role alone instead of re-stating it, this player would silently host.
	# Under the frontmatter the back-out is `FrontmatterRoot.back()` rather than
	# a stack pop, but the thing being asserted is unchanged: what the next
	# route leaves on GameSession.
	_dial("Host")
	assert_eq(GameSession.network.role, NetworkTransport.Role.HOST)

	_back_out(2)  # out of the lobby panel, then out of Multiplayer
	_navigate_to(MenuGraph.ID_NEW_GAME)

	assert_eq(GameSession.network.role, NetworkTransport.Role.OFFLINE)
	assert_false(GameSession.network.is_online(), "hosting did not survive the back-out")


func test_every_lobby_route_writes_a_network_config() -> void:
	# Not one of them leaves GameSession.network as it found it — that is the
	# invariant, stated over all four routes at once.
	for id in [MenuGraph.ID_NEW_GAME, MenuGraph.ID_LOCAL]:
		GameSession.network = null
		_navigate_to(id)
		assert_not_null(GameSession.network, "'%s' states a role" % id)
		_back_out(_tree.depth_of(id))

	for button in ["Host", "Join"]:
		GameSession.network = null
		_dial(button)
		assert_not_null(GameSession.network, "'%s' states a role" % button)
		_back_out(2)


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
	_navigate_to(MenuGraph.ID_OPTIONS)
	assert_eq(_panels.shown_panel, MenuGraph.PANEL_SETTINGS)
	assert_true(_panels.get_panel(MenuGraph.PANEL_SETTINGS) is FrontmatterPanel)
	assert_null(GameSession.network, "opening options is not a route into a run")

	var item := _tree.get_item(MenuGraph.ID_OPTIONS)
	assert_eq(item.panel, MenuGraph.PANEL_SETTINGS)
	assert_null(item.route, "settings authors no run")


func test_quit_is_wired_to_exactly_one_thing() -> void:
	# Deliberately NOT pressed through `_meta`: the shell connects this to
	# `get_tree().quit()`, which would end the test run. So the wiring is
	# asserted here and the signal itself on a standalone panel below.
	_open_menu()
	assert_eq(_panels.quit_requested.get_connections().size(), 1)

	var item := _tree.get_item(MenuGraph.ID_EXIT)
	assert_eq(item.panel, MenuGraph.PANEL_EXIT_CONFIRM,
			"the frontmatter asks first — #567's exit confirm is a panel, not a modal")
	assert_null(item.route)


func test_the_quit_option_emits_rather_than_quitting_by_itself() -> void:
	var standalone: ExitConfirmPanel = preload(
			"res://ui/frontmatter/panels/exit_confirm_panel.tscn").instantiate()
	add_child_autofree(standalone)
	var fired: Array[int] = []
	standalone.quit_requested.connect(func(): fired.append(1))
	standalone._confirm_button.pressed.emit()
	assert_eq(fired.size(), 1, "the panel emits; the shell decides that means quit")


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


func test_every_route_into_a_lobby_names_its_lobby_policy() -> void:
	# #615 D2: the policy hangs on the ROUTE, not on a `Mode -> policy` table,
	# because `requested_mode` is explicitly not authoritative — HOST and JOIN
	# both ask for COOP_HOTSEAT and both open the versus lobby.
	for id in _tree.ids():
		var item := _tree.get_item(id)
		if item.route == null:
			continue
		assert_not_null(item.route.lobby_policy, "'%s' names a lobby policy" % id)
	assert_ne(_tree.get_item(MenuGraph.ID_NEW_GAME).route.lobby_policy,
			_tree.get_item(MenuGraph.ID_HOST).route.lobby_policy,
			"solo and versus are not the same lobby")


func test_a_route_hands_its_policy_to_the_lobby_it_opens() -> void:
	# The wiring half: `_push_lobby` carries the leaf's policy through
	# `LobbyPanel.configure` into the screen. Asserted on all three lobby leaves
	# plus #531's address-screen path, which cannot read `item.route` on focus.
	for id in [MenuGraph.ID_NEW_GAME, MenuGraph.ID_LOCAL, MenuGraph.ID_HOST]:
		_navigate_to(id)
		assert_eq(_lobby()._policy, _tree.get_item(id).route.lobby_policy,
				"'%s' hands its policy down" % id)
		_back_out(_tree.depth_of(id))

	assert_eq(_dial("Join", "10.0.0.4", "7777")._policy,
			_tree.get_item(MenuGraph.ID_JOIN).route.lobby_policy,
			"and so does the address screen, which has no leaf focus to read")


func test_the_parked_load_screen_starts_nothing() -> void:
	var item := _tree.get_item(MenuGraph.ID_LOAD_GAME)
	assert_true(item.disabled, "#23 save/load is parked; today's screen disables it too")
	assert_null(item.route)
	assert_eq(item.panel, MenuGraph.PANEL_LOAD)


# --- the splash draws in SCREEN space ----------------------------------------

func test_the_splash_lives_in_a_canvas_layer() -> void:
	# `%Camera` is a Camera2D, and a Camera2D transforms the viewport's DEFAULT
	# canvas — which a plain Control child of `MetaRoot` is on. So the title and
	# the "PRESS ANY BUTTON" prompt were panned and zoomed with the tree and sat
	# entirely off screen: at FrontmatterLayout.SPLASH_ZOOM there was no splash
	# text at all, and no error to say so. Same reason `frontmatter_root.tscn`
	# puts its tooltip and its panels on a CanvasLayer.
	var splash := _meta.get_node("%Splash") as SplashScreen
	assert_not_null(splash)
	var layered := false
	var walk: Node = splash.get_parent()
	while walk != null and walk != _meta:
		if walk is CanvasLayer:
			layered = true
			break
		walk = walk.get_parent()
	assert_true(layered,
			"the splash's own text is screen space — the camera must not move it")
