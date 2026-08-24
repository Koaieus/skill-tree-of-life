extends GutTest

## The frontmatter's panel layer (#573) — the seam the navigation state machine
## calls, and the five panels behind it.
##
## [b]What this pins is the seam, not the pixels.[/b] #567's testing contract
## puts glow, easing and "does it look good" on the sandbox tab and the owner's
## eye; what is decidable in code is which panel is up, that exactly one is, and
## that dismissing one hands the stage back to the graph. So every assertion
## below is about [FrontmatterPanels]' four public calls and the one signal C3
## consumes.
##
## The lobby and join panels host the SHIPPED [LobbyScreen] / [HostJoinScreen]
## by composition rather than reimplementing them, so what is asserted about
## them here is only the seam: that the screen is reachable, that its signals
## are relayed, and that #553/#554's roster logic still answers through the
## panel. `test_lobby_roster.gd` and `test_host_join_screen.gd` remain the tests
## OF those screens and are untouched by this unit — if they and these ever
## disagree, they are right and this is wrong.

const _PANELS := preload("res://ui/frontmatter/panels/frontmatter_panels.tscn")

var _panels: FrontmatterPanels


func before_each() -> void:
	_panels = _PANELS.instantiate()
	add_child_autofree(_panels)


# --- registration is by existing, not by table -------------------------------

func test_every_registered_id_is_a_menu_graph_panel_constant() -> void:
	# The ids are set in the inspector on each inherited scene, so the thing
	# that can drift is a typo'd StringName. Nothing else catches that.
	var known := [
		MenuGraph.PANEL_LOBBY,
		MenuGraph.PANEL_LOAD,
		MenuGraph.PANEL_JOIN,
		MenuGraph.PANEL_SETTINGS,
		MenuGraph.PANEL_EXIT_CONFIRM,
	]
	for id in _panels.panel_ids():
		assert_true(id in known, "'%s' is not a MenuGraph panel id" % id)


func test_every_panel_the_menu_tree_names_is_registered() -> void:
	# The tree's leaves are the demand side; this container is the supply side.
	# A leaf naming a panel nobody built routes into a no-op, which is exactly
	# what LOAD GAME did before this unit and what nothing else should do.
	var tree := MenuGraph.build()
	for id in tree.ids():
		var item := tree.get_item(id)
		if item.panel == &"":
			continue
		assert_true(_panels.has_panel(item.panel),
				"leaf '%s' names panel '%s', which nothing supplies" % [id, item.panel])


func test_all_five_panels_are_registered() -> void:
	assert_eq(_panels.panel_ids().size(), 5)
	assert_true(_panels.has_panel(MenuGraph.PANEL_SETTINGS))
	assert_true(_panels.has_panel(MenuGraph.PANEL_LOAD))
	assert_true(_panels.has_panel(MenuGraph.PANEL_EXIT_CONFIRM))
	assert_true(_panels.has_panel(MenuGraph.PANEL_LOBBY))
	assert_true(_panels.has_panel(MenuGraph.PANEL_JOIN))


func test_each_registered_panel_answers_to_its_own_id() -> void:
	for id in _panels.panel_ids():
		assert_eq(_panels.get_panel(id).panel_id, id)


func test_the_settings_panel_hosts_the_reflected_settings_menu() -> void:
	# #573: "do not author fake sliders". The canvas mockup's Music / SFX /
	# Brightness do not exist in GameSettings; the real menu walks
	# `get_property_list()` and is reused whole.
	var settings := _panels.get_panel(MenuGraph.PANEL_SETTINGS)
	var found := false
	for child in settings.body.get_children():
		if child is SettingsMenu:
			found = true
	assert_true(found, "the settings panel instances settings_menu.tscn")


func test_the_load_panel_is_present_but_carries_nothing() -> void:
	# #23 save/load is parked; LOAD GAME still has to route somewhere.
	var load_panel := _panels.get_panel(MenuGraph.PANEL_LOAD)
	assert_not_null(load_panel)
	assert_eq(load_panel.panel_id, MenuGraph.PANEL_LOAD)


# --- exactly one panel is up, or none ----------------------------------------

func test_nothing_is_up_to_start_with() -> void:
	assert_eq(_panels.shown_panel, &"")
	assert_false(_panels.visible, "the graph layer has the stage")


func test_showing_a_panel_raises_it_and_only_it() -> void:
	_panels.show_panel(MenuGraph.PANEL_SETTINGS)

	assert_eq(_panels.shown_panel, MenuGraph.PANEL_SETTINGS)
	assert_true(_panels.visible)
	for id in _panels.panel_ids():
		assert_eq(_panels.get_panel(id).visible, id == MenuGraph.PANEL_SETTINGS,
				"only '%s' is up" % MenuGraph.PANEL_SETTINGS)


func test_showing_a_second_panel_replaces_rather_than_stacks() -> void:
	# There is no stack. #567 replaced the breadcrumb with the graph itself, so
	# two panels up at once would be the old shape creeping back.
	_panels.show_panel(MenuGraph.PANEL_SETTINGS)
	_panels.show_panel(MenuGraph.PANEL_LOAD)

	assert_eq(_panels.shown_panel, MenuGraph.PANEL_LOAD)
	assert_false(_panels.get_panel(MenuGraph.PANEL_SETTINGS).visible)


func test_hide_all_returns_the_stage_to_the_graph() -> void:
	_panels.show_panel(MenuGraph.PANEL_SETTINGS)
	_panels.hide_all()

	assert_eq(_panels.shown_panel, &"")
	assert_false(_panels.visible)
	for id in _panels.panel_ids():
		assert_false(_panels.get_panel(id).visible)


func test_an_unlanded_panel_is_a_no_op_rather_than_a_crash() -> void:
	# A leaf whose panel has not landed yet still routes. `shown_panel` records
	# what was ASKED for — `test_frontmatter_layout.gd` pins exactly that
	# against an empty container — while `has_panel` is what decides whether
	# this layer takes the stage, so an unlanded leaf leaves the graph up.
	_panels.show_panel(MenuGraph.PANEL_SETTINGS)
	_panels.show_panel(&"not_a_panel")

	assert_false(_panels.has_panel(&"not_a_panel"))
	assert_eq(_panels.shown_panel, &"not_a_panel")
	assert_false(_panels.visible, "nothing to raise, so the graph keeps the stage")
	assert_false(_panels.get_panel(MenuGraph.PANEL_SETTINGS).visible)


# --- dismissal is the graph's business ---------------------------------------

func test_a_panel_dismissing_itself_reports_its_id_upward() -> void:
	var seen: Array[StringName] = []
	_panels.panel_dismissed.connect(func(id: StringName): seen.append(id))

	_panels.show_panel(MenuGraph.PANEL_SETTINGS)
	_panels.get_panel(MenuGraph.PANEL_SETTINGS).back_button.pressed.emit()

	assert_eq(seen, [MenuGraph.PANEL_SETTINGS] as Array[StringName])
	assert_eq(_panels.shown_panel, &"", "dismissing hands the stage back")


func test_dismissing_a_panel_that_is_not_up_reports_but_does_not_hide() -> void:
	var seen: Array[StringName] = []
	_panels.panel_dismissed.connect(func(id: StringName): seen.append(id))

	_panels.show_panel(MenuGraph.PANEL_SETTINGS)
	_panels.get_panel(MenuGraph.PANEL_LOAD).dismiss()

	assert_eq(seen, [MenuGraph.PANEL_LOAD] as Array[StringName])
	assert_eq(_panels.shown_panel, MenuGraph.PANEL_SETTINGS,
			"a stale dismissal does not pull down the live panel")


# --- the exit confirm emits rather than quitting -----------------------------

func test_the_exit_confirm_is_a_panel_and_not_a_modal() -> void:
	# `.claude/rules/modal-system.md` routes modals through HudRoot; the menu
	# has no HudRoot, and #573 says so explicitly. It is one of these five.
	var exit_confirm := _panels.get_panel(MenuGraph.PANEL_EXIT_CONFIRM)
	assert_true(exit_confirm is ExitConfirmPanel)
	assert_true(exit_confirm is FrontmatterPanel)


func test_confirming_the_exit_emits_rather_than_quitting_by_itself() -> void:
	# Pressed for real, which is only safe BECAUSE nothing below the shell
	# calls SceneTree.quit — the same split the deleted main menu shipped for
	# its own quit_pressed.
	var fired: Array[int] = []
	_panels.quit_requested.connect(func(): fired.append(1))

	var exit_confirm := _panels.get_panel(MenuGraph.PANEL_EXIT_CONFIRM) as ExitConfirmPanel
	exit_confirm._confirm_button.pressed.emit()

	assert_eq(fired.size(), 1, "the panel emits; the shell decides that means quit")


func test_backing_out_of_the_exit_confirm_quits_nothing() -> void:
	var fired: Array[int] = []
	_panels.quit_requested.connect(func(): fired.append(1))

	_panels.show_panel(MenuGraph.PANEL_EXIT_CONFIRM)
	_panels.get_panel(MenuGraph.PANEL_EXIT_CONFIRM).back_button.pressed.emit()

	assert_eq(fired.size(), 0, "STAY is not QUIT")
	assert_eq(_panels.shown_panel, &"")


# --- the lobby is re-homed, not rewritten ------------------------------------

func _humans(participants: Array[Participant]) -> Array[Participant]:
	var out: Array[Participant] = []
	for p in participants:
		if p.kind != Participant.Kind.AI:
			out.append(p)
	return out


func _lobby() -> LobbyPanel:
	return _panels.get_panel(MenuGraph.PANEL_LOBBY) as LobbyPanel


func test_the_lobby_panel_hosts_the_shipped_screen_rather_than_a_copy() -> void:
	var lobby := _lobby()
	assert_null(lobby.screen, "nothing is built until a route configures one")

	lobby.configure(RunConfig.Mode.SINGLE, NetworkConfig.offline())

	assert_not_null(lobby.screen)
	assert_true(lobby.screen is LobbyScreen,
			"#553/#554's roster logic is reached, not reimplemented")


func test_the_roster_logic_still_answers_through_the_panel() -> void:
	# The narrow claim: `build_run_config()` reached through the panel produces
	# the same shape `test_meta_routing_parity.gd` gets by walking the tree.
	# If this drifts, the re-home lost #553/#554.
	var lobby := _lobby()
	lobby.configure(RunConfig.Mode.SINGLE, NetworkConfig.offline())

	var cfg := lobby.screen.build_run_config()
	assert_eq(cfg.mode, RunConfig.Mode.SINGLE)
	assert_eq(_humans(cfg.participants).size(), 1)


func test_a_networked_route_still_seats_the_absent_player_up_front() -> void:
	# #554 D2 through the panel: the joiner's seat exists before anyone joins,
	# and the roster answers VERSUS even though the route asked for coop.
	var lobby := _lobby()
	lobby.configure(RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.host(7777))

	var cfg := lobby.screen.build_run_config()
	var humans := _humans(cfg.participants)
	assert_eq(humans.size(), 2)
	assert_true(LobbyScreen.is_pending_remote(humans[1]), "the joiner's seat is waiting")
	assert_eq(cfg.mode, RunConfig.Mode.VERSUS, "the ROSTER answers, not the button")


func test_configuring_again_replaces_the_lobby_rather_than_stacking_one() -> void:
	# Backing out of a host route and taking a solo one must not leave the
	# previous lobby's roster — or its node — behind.
	var lobby := _lobby()
	lobby.configure(RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.host(7777))
	lobby.configure(RunConfig.Mode.SINGLE, NetworkConfig.offline())

	var screens := 0
	for child in lobby.body.get_children():
		if child is LobbyScreen and not child.is_queued_for_deletion():
			screens += 1
	assert_eq(screens, 1, "exactly one lobby is mounted")

	var cfg := lobby.screen.build_run_config()
	assert_eq(cfg.mode, RunConfig.Mode.SINGLE, "the host route left nothing behind")


func test_start_is_relayed_upward_with_its_run_config() -> void:
	# The panel carries the RunConfig up; it does not call GameSession.start
	# itself. That decision is the shell's, as it is meta_root.gd's today.
	var lobby := _lobby()
	lobby.configure(RunConfig.Mode.SINGLE, NetworkConfig.offline())

	var seen: Array[RunConfig] = []
	lobby.start_pressed.connect(func(cfg: RunConfig): seen.append(cfg))
	lobby.screen.start_pressed.emit(lobby.screen.build_run_config())

	assert_eq(seen.size(), 1)
	assert_eq(seen[0].mode, RunConfig.Mode.SINGLE)


func test_the_lobby_panels_back_button_dismisses_it() -> void:
	# Since #579 the back button is the PANEL's — the hosted screen carries no
	# chrome of its own, so there is exactly one of them rather than two.
	var lobby := _lobby()
	lobby.configure(RunConfig.Mode.SINGLE, NetworkConfig.offline())
	_panels.show_panel(MenuGraph.PANEL_LOBBY)

	var seen: Array[StringName] = []
	_panels.panel_dismissed.connect(func(id: StringName): seen.append(id))
	lobby.back_button.pressed.emit()

	assert_eq(seen, [MenuGraph.PANEL_LOBBY] as Array[StringName])
	assert_eq(_panels.shown_panel, &"")


# --- the join panel keeps the shipped address handling -----------------------

func _join() -> JoinPanel:
	return _panels.get_panel(MenuGraph.PANEL_JOIN) as JoinPanel


func _press(screen: HostJoinScreen, text: String) -> void:
	for child in screen.content.get_children():
		if child is Button and (child as Button).text == text:
			(child as Button).pressed.emit()
			return
	fail_test("no button labelled '%s'" % text)


func test_the_join_panel_hosts_the_shipped_screen() -> void:
	assert_not_null(_join().screen)
	assert_true(_join().screen is HostJoinScreen)


func test_the_typed_address_and_port_reach_the_relay_intact() -> void:
	# #573 names `host_join_screen.gd`'s address/port handling as something to
	# re-home rather than rewrite. This is that handling, reached through the
	# panel: what the player typed is what comes out.
	var join := _join()
	join.screen._address_edit.text = "192.168.1.7"
	join.screen._port_edit.text = "7777"

	var seen: Array = []
	join.join_requested.connect(func(a: String, p: int): seen.append([a, p]))
	_press(join.screen, "Join")

	assert_eq(seen, [["192.168.1.7", 7777]])


func test_a_blank_address_still_falls_back_rather_than_dialling_nothing() -> void:
	# The `_address()` fallback comment #573 calls out. Asserted through the
	# panel so the re-home cannot quietly drop it.
	var join := _join()
	join.screen._address_edit.text = ""
	join.screen._port_edit.text = "7777"

	var seen: Array = []
	join.join_requested.connect(func(a: String, p: int): seen.append(a))
	_press(join.screen, "Join")

	assert_eq(seen.size(), 1)
	assert_ne(seen[0], "", "an empty field falls back to the default address")


func test_the_join_panels_back_button_dismisses_it() -> void:
	var join := _join()
	_panels.show_panel(MenuGraph.PANEL_JOIN)

	var seen: Array[StringName] = []
	_panels.panel_dismissed.connect(func(id: StringName): seen.append(id))
	join.back_button.pressed.emit()

	assert_eq(seen, [MenuGraph.PANEL_JOIN] as Array[StringName])
	assert_eq(_panels.shown_panel, &"")
