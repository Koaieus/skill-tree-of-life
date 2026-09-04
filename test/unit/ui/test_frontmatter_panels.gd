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
## The lobby panel hosts the SHIPPED [LobbyScreen] by composition rather than
## reimplementing it, so what is asserted about it here is only the seam: that
## the screen is reachable, that its signals are relayed, and that #553/#554's
## roster logic still answers through the panel. The two network panels
## ([HostPanel], [JoinPanel]) author their own bodies since #582 and share
## [NetworkFields]; only their relay is asserted here.
## `test_lobby_roster.gd` and `test_network_entry_panels.gd` remain the tests OF
## those bodies and are untouched by this unit — if they and these ever
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
		MenuGraph.PANEL_HOST,
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


func test_all_six_panels_are_registered() -> void:
	assert_eq(_panels.panel_ids().size(), 6)
	assert_true(_panels.has_panel(MenuGraph.PANEL_SETTINGS))
	assert_true(_panels.has_panel(MenuGraph.PANEL_LOAD))
	assert_true(_panels.has_panel(MenuGraph.PANEL_EXIT_CONFIRM))
	assert_true(_panels.has_panel(MenuGraph.PANEL_LOBBY))
	assert_true(_panels.has_panel(MenuGraph.PANEL_JOIN))
	assert_true(_panels.has_panel(MenuGraph.PANEL_HOST))


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
	_panels.get_panel(MenuGraph.PANEL_SETTINGS).dismiss()

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
	_panels.get_panel(MenuGraph.PANEL_EXIT_CONFIRM).dismiss()

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


func test_the_lobby_panel_dismisses_via_dismiss() -> void:
	# Since #600 there is one back affordance (the graph's, in the hero
	# column) rather than a per-panel button — the panel's own escape is
	# `dismiss()`, exercised the same way the exit-confirm's "no" path uses it.
	var lobby := _lobby()
	lobby.configure(RunConfig.Mode.SINGLE, NetworkConfig.offline())
	_panels.show_panel(MenuGraph.PANEL_LOBBY)

	var seen: Array[StringName] = []
	_panels.panel_dismissed.connect(func(id: StringName): seen.append(id))
	lobby.dismiss()

	assert_eq(seen, [MenuGraph.PANEL_LOBBY] as Array[StringName])
	assert_eq(_panels.shown_panel, &"")


## #610/#611 acceptance 4: every OTHER lobby test in this file calls
## `configure()` by hand on a bare `frontmatter_panels.tscn` — #610 exists
## because that never exercised the real navigation path, so this one boots
## the whole shell (`meta_root.tscn`) and walks it, same as
## `test_meta_routing_parity.gd`'s `_navigate_to`. Does not use [member
## _panels] / [member before_each] on purpose: those are the bare container
## this test is specifically avoiding.
##
## The leading hypothesis in #610 — `_constrain_column_width()` pinning
## `%Column` to a zero-width shrink — did not reproduce once #603's re-home
## landed (probed by hand: `%Body`'s children already carried real, non-zero
## sizes before #611 touched anything). This stays as the regression net
## #610 asks for regardless of which unit actually fixed it.
func test_navigating_to_new_game_renders_a_real_lobby() -> void:
	var meta: Control = load("res://scenes/meta/meta_root.tscn").instantiate()
	add_child_autofree(meta)
	var frontmatter: FrontmatterRoot = meta.get_node("%Frontmatter")
	(meta.get_node("%Splash") as SplashScreen).advanced.emit()
	for step in frontmatter.tree.path_to(MenuGraph.ID_NEW_GAME):
		frontmatter.focus(step, true)
	await wait_frames(2)

	var found := frontmatter.find_children("*", "FrontmatterPanels", true, false)
	var panels := found[0] as FrontmatterPanels
	assert_eq(panels.shown_panel, MenuGraph.PANEL_LOBBY, "the leaf routed to the lobby")
	assert_true(panels.visible, "the panel layer took the stage")

	var lobby_panel := panels.get_panel(MenuGraph.PANEL_LOBBY) as LobbyPanel
	assert_true(lobby_panel.visible, "the lobby panel itself is shown")
	var screen := lobby_panel.screen
	assert_not_null(screen, "configure() minted a real LobbyScreen")
	assert_gt(screen.size.x, 0.0, "the screen has real width, not a collapsed column")

	# Participant rows: the rendered nodes, not just the data array — #610 was
	# about the UI reading empty, which a non-empty `participants()` alone
	# would not have caught.
	assert_gt(screen._rows_container.get_child_count(), 0, "at least one participant row rendered")
	assert_gt(screen.participants().size(), 0, "and the roster behind it is non-empty")

	# Recursive: the spinner and the seed field each sit inside their own row
	# (an HBoxContainer child of the screen), not directly on it.
	assert_false(screen.find_children("*", "SpinBox", true, false).is_empty(),
			"the AI-opponents spinner rendered")
	assert_false(screen.find_children("*", "LineEdit", true, false).is_empty(),
			"the seed field rendered")
	var found_start_button := false
	for button in screen.find_children("*", "Button", true, false):
		if (button as Button).text == "Start Game":
			found_start_button = true
	assert_true(found_start_button, "the Start button rendered")


# --- the network panels keep the shipped address handling --------------------

func _join() -> JoinPanel:
	return _panels.get_panel(MenuGraph.PANEL_JOIN) as JoinPanel


func _host() -> HostPanel:
	return _panels.get_panel(MenuGraph.PANEL_HOST) as HostPanel


func test_both_network_panels_carry_the_shared_fields() -> void:
	assert_not_null(_join().fields)
	assert_not_null(_host().fields, "#582: HOST types a port before the lobby")


func test_the_typed_address_and_port_reach_the_relay_intact() -> void:
	# #573 named the old screen's address/port handling as something to re-home
	# rather than rewrite; #582 re-homed it into [NetworkFields]. This is that
	# handling, reached through the panel: what the player typed is what comes
	# out.
	var join := _join()
	join.fields._address_edit.text = "192.168.1.7"
	join.fields._port_edit.text = "7777"

	var seen: Array = []
	join.join_requested.connect(func(a: String, p: int): seen.append([a, p]))
	join._join_button.pressed.emit()

	assert_eq(seen, [["192.168.1.7", 7777]])


func test_the_typed_port_reaches_the_relay_from_the_host_panel_too() -> void:
	var host := _host()
	host.fields._port_edit.text = "7777"

	var seen: Array = []
	host.host_requested.connect(func(p: int): seen.append(p))
	host._host_button.pressed.emit()

	assert_eq(seen, [7777])


func test_a_blank_address_is_refused_on_the_panel_rather_than_dialled() -> void:
	# This used to pin #573's `address()` fallback to loopback. #752 inverted
	# it: the fallback is how a joiner who left the box alone dialled ITSELF, so
	# a blank address now goes nowhere and says so. Still asserted through the
	# panel, so the re-home cannot quietly drop the refusal either.
	var join := _join()
	join.fields._address_edit.text = ""
	join.fields._port_edit.text = "7777"

	var seen: Array = []
	join.join_requested.connect(func(a: String, _p: int): seen.append(a))
	join._join_button.pressed.emit()

	assert_eq(seen, [], "nothing is dialled")
	assert_eq(join.status_text(), NetworkConfig.BLANK_ADDRESS_PROBLEM,
			"and the panel says why, with the field left for the retry")


func test_the_join_panel_dismisses_via_dismiss() -> void:
	var join := _join()
	_panels.show_panel(MenuGraph.PANEL_JOIN)

	var seen: Array[StringName] = []
	_panels.panel_dismissed.connect(func(id: StringName): seen.append(id))
	join.dismiss()

	assert_eq(seen, [MenuGraph.PANEL_JOIN] as Array[StringName])
	assert_eq(_panels.shown_panel, &"")


# --- #600: chrome reshape -----------------------------------------------------

## No per-panel back button, and nothing spanning the full rect can eat the
## clicks the graph-space `BackAffordance` needs.
##
## Re-pointed: this used to also assert no `ColorRect` anywhere in the tree,
## back when a `ColorRect` could only mean an accidental opaque backdrop. #611
## D2 authors a [GlassPanel] — a `ColorRect` under the hood — as the base
## panel's own deliberate chrome, so that blanket check would now fail on
## exactly the thing it is supposed to have. The click-safety concern it was
## really guarding is [method _assert_no_full_rect_stop], which still checks
## every `Control` in the tree, glass included.
func test_the_base_panel_has_no_back_button_and_nothing_eats_clicks() -> void:
	var panel: FrontmatterPanel = preload("res://ui/frontmatter/panels/frontmatter_panel.tscn").instantiate()
	add_child_autofree(panel)

	# `find_children`'s type filter matches a script `class_name`; `_find_type`
	# below only matches `get_class()`, which is `ColorRect` for a `GlassPanel`.
	assert_false(panel.find_children("*", "GlassPanel", true, false).is_empty(),
			"the base chrome authors its own glass now")
	assert_null(panel.get_node_or_null("BackButton"), "no per-panel back button")
	_assert_no_full_rect_stop(panel)


func _find_type(node: Node, class_name_: String) -> Node:
	if node.get_class() == class_name_:
		return node
	for child in node.get_children():
		var found := _find_type(child, class_name_)
		if found != null:
			return found
	return null


func _assert_no_full_rect_stop(node: Node) -> void:
	if node is Control:
		var control := node as Control
		var spans_full_rect := (
			control.anchor_left == 0.0 and control.anchor_top == 0.0
			and control.anchor_right == 1.0 and control.anchor_bottom == 1.0
			and control.offset_left == 0.0 and control.offset_top == 0.0
			and control.offset_right == 0.0 and control.offset_bottom == 0.0
		)
		if spans_full_rect:
			assert_ne(control.mouse_filter, Control.MOUSE_FILTER_STOP,
					"'%s' spans the full rect and would eat clicks" % control.name)
	for child in node.get_children():
		_assert_no_full_rect_stop(child)


## #600's replacement chrome: the region's left edge sits past the hero
## column, its right edge at the viewport edge — read off [FrontmatterLayout],
## never a literal.
## Re-pointed by #603 D5/D6: `%Region` is gone. This scene's own root IS the
## region now — it is parented straight into `frontmatter_columns.tscn`'s
## `%Remainder` (`frontmatter_root.tscn`), so the panel gets its rect from
## CONTAINER layout and no longer computes one off [FrontmatterLayout]. What
## survives to test is that the panel authors no anchored stand-in that
## recomputes it: the root fills its given rect by anchors alone, with no
## per-panel offset literal.
func test_the_panel_root_fills_its_column_with_no_offset_of_its_own() -> void:
	var panel: FrontmatterPanel = preload("res://ui/frontmatter/panels/frontmatter_panel.tscn").instantiate()
	add_child_autofree(panel)

	assert_null(panel.get_node_or_null("%Region"), "no anchored stand-in for the region")
	assert_eq(panel.anchor_left, 0.0)
	assert_eq(panel.anchor_top, 0.0)
	assert_eq(panel.anchor_right, 1.0)
	assert_eq(panel.anchor_bottom, 1.0)
	assert_eq(panel.offset_left, 0.0, "no left-edge literal — the column supplies it")
	assert_eq(panel.offset_right, 0.0)


## Retired by #611 D3, not re-pointed: `#606`'s `_CONTENT_MAX_WIDTH` was a
## compensation for a row that stretched to strand its label from its
## control, not a legibility bound — #609 fixed the row-layout cause
## directly, so bounding the COLUMN'S width is no longer this scene's job at
## all. The issue names this exact deletion (`test_frontmatter_panels.gd:432`
## at the time of writing). What survives the reshape — the glass visibly
## inset from the viewport, headers above content — is
## `test_the_base_panel_reshapes_into_outer_margin_glass_inner_margin` below.


## #611 D2, acceptance 1: outer margin -> glass -> inner margin -> title +
## body, in that order, and the outer margin is what insets the glass from
## the viewport's own top/right/bottom (a pixel diff is `#603`'s C4 kind of
## check, not this file's — this pins the STRUCTURE the screenshot depends on).
func test_the_base_panel_reshapes_into_outer_margin_glass_inner_margin() -> void:
	var panel: FrontmatterPanel = preload("res://ui/frontmatter/panels/frontmatter_panel.tscn").instantiate()
	add_child_autofree(panel)

	var outer := panel.get_node("%OuterMargin") as MarginContainer
	assert_eq(outer.get_parent(), panel, "the outer margin is the panel's own first child")
	assert_gt(outer.get_theme_constant(&"margin_top"), 0, "inset from the top")
	assert_gt(outer.get_theme_constant(&"margin_right"), 0, "inset from the right")
	assert_gt(outer.get_theme_constant(&"margin_bottom"), 0, "inset from the bottom")

	var glass := outer.find_children("*", "GlassPanel", false, false)
	assert_eq(glass.size(), 1, "exactly one glass panel, direct child of the outer margin")
	var glass_panel := glass[0] as Control

	var inner := glass_panel.get_node("%InnerMargin") as MarginContainer
	assert_eq(inner.get_parent(), glass_panel, "the inner margin is inside the glass, not beside it")

	var column := inner.get_node("%Column")
	assert_eq(column.get_parent(), inner, "content sits inside the inner margin")
	assert_eq(panel.get_node("%Title").get_parent(), column)
	assert_eq(panel.get_node("%Body").get_parent(), column)


## #611 D4: every inherited panel gets this frame from the ONE base scene.
## No inherited scene repeats a margin or re-declares the glass — each just
## fills `%Body`.
func test_every_inherited_panel_gets_the_frame_from_the_base_scene_alone() -> void:
	for path in [
		"res://ui/frontmatter/panels/settings_panel.tscn",
		"res://ui/frontmatter/panels/load_panel.tscn",
		"res://ui/frontmatter/panels/exit_confirm_panel.tscn",
		"res://ui/frontmatter/panels/lobby_panel.tscn",
		"res://ui/frontmatter/panels/join_panel.tscn",
		"res://ui/frontmatter/panels/host_panel.tscn",
	]:
		var panel: FrontmatterPanel = load(path).instantiate()
		add_child_autofree(panel)
		assert_not_null(panel.get_node_or_null("%OuterMargin"), "%s inherits the outer margin" % path)
		assert_not_null(panel.get_node_or_null("%InnerMargin"), "%s inherits the inner margin" % path)
		assert_eq(
			panel.find_children("*", "GlassPanel", true, false).size(), 1,
			"%s inherits exactly one glass panel, never authors its own" % path,
		)


## No [FrontmatterPanel] subclass may reach across the layer split — that
## invariant is what keeps panel text crisp instead of panned and zoomed by the
## graph camera. `FrontmatterPanels` (the container) and content mounted into
## `%Body` ([LobbyScreen], [NetworkFields]) are not subclasses of
## [FrontmatterPanel] and are excluded on purpose.
func test_no_panel_subclass_reaches_across_the_layer_split() -> void:
	var scripts := [
		"res://ui/frontmatter/panels/settings_panel.gd",
		"res://ui/frontmatter/panels/exit_confirm_panel.gd",
		"res://ui/frontmatter/panels/lobby_panel.gd",
		"res://ui/frontmatter/panels/join_panel.gd",
		"res://ui/frontmatter/panels/host_panel.gd",
	]
	var forbidden := ["Camera2D", "%GraphLayer", "get_viewport_transform"]
	for path in scripts:
		if not ResourceLoader.exists(path):
			continue
		var source := FileAccess.get_file_as_string(path)
		for needle in forbidden:
			assert_false(source.contains(needle), "%s must not reference '%s'" % [path, needle])


## The end-to-end acceptance for #600: with a panel up, the graph's own
## [BackAffordance] is reachable and pressing it both returns focus to the
## parent and takes the panel down — the affordance -> `back()` -> `hide_all()`
## chain, through the whole shell rather than through the seam alone. Lives
## here rather than in `test_frontmatter_navigation.gd` because it needs
## `FrontmatterPanels`' own container, not just the graph.
func test_pressing_the_back_affordance_with_a_panel_up_returns_to_the_parent() -> void:
	var root: FrontmatterRoot = preload("res://ui/frontmatter/frontmatter_root.tscn").instantiate()
	add_child_autofree(root)
	root.reduce_motion = true

	root.focus(MenuGraph.ID_OPTIONS, true)

	# Found by type, not the literal path: #603 D6 nests the container inside
	# `frontmatter_columns.tscn`'s `%Remainder`, so it is no longer a direct
	# child of `%PanelLayer` under a fixed name.
	var found := root.get_node("%PanelLayer").find_children("*", "FrontmatterPanels", true, false)
	var panels: FrontmatterPanels = found[0] as FrontmatterPanels
	assert_eq(panels.shown_panel, MenuGraph.PANEL_SETTINGS, "the leaf routed its panel")

	var back_affordance: Node = root.get_node("%BackAffordance")
	assert_true(back_affordance.visible, "reachable while a panel is up (#600 deletes the backdrop)")

	back_affordance.press()

	assert_eq(root.focus_id, MenuGraph.ID_ROOT, "back() moved the focus")
	assert_eq(panels.shown_panel, &"", "and hid the panel")


# --- #613: rows are scenes, not code-composed trees -------------------------

func test_participant_row_configures_with_color_name_and_seat() -> void:
	var row: ParticipantRow = preload("res://ui/frontmatter/panels/participant_row.tscn").instantiate()
	add_child_autofree(row)

	var p := Participant.new()
	p.display_name = "Test Player"
	p.color = Color.RED
	p.kind = Participant.Kind.HUMAN
	p.peer_id = 0

	row.configure(p, 0)

	assert_eq(row.get_node("%Swatch").color, Color.RED, "swatch color matches participant")
	assert_eq(row.get_node("%Name").text, "Test Player", "name matches participant")
	assert_eq(row.get_node("%Seat").text, "you", "seat text is 'you' for local peer")


func test_ai_count_slider_and_spinbox_stay_linked() -> void:
	var row: AiCountRow = preload("res://ui/frontmatter/panels/ai_count_row.tscn").instantiate()
	add_child_autofree(row)

	var slider: HSlider = row.get_node("%Slider")
	var spinbox: SpinBox = row.get_node("%SpinBox")

	slider.value = 3.0
	await get_tree().process_frame
	assert_eq(spinbox.value, 3.0, "spinbox follows slider")

	spinbox.value = 2.0
	await get_tree().process_frame
	assert_eq(slider.value, 2.0, "slider follows spinbox")


func test_ai_count_row_does_not_jump_when_ai_count_changes() -> void:
	var lobby := _lobby()
	lobby.configure(RunConfig.Mode.SINGLE, NetworkConfig.offline())
	_panels.show_panel(MenuGraph.PANEL_LOBBY)
	await get_tree().process_frame

	var ai_row: AiCountRow = lobby.screen._ai_count_row
	var initial_y := ai_row.global_position.y

	ai_row.value = 4.0
	await get_tree().process_frame

	var final_y := ai_row.global_position.y
	assert_eq(final_y, initial_y, "AI count row y-position unchanged after changing count")


func test_no_hbox_containers_code_composed_in_lobby_screen() -> void:
	# Acceptance test 1: grep for HBoxContainer.new() in the two row builders
	var source := FileAccess.get_file_as_string("res://ui/frontmatter/panels/lobby_screen.gd")
	var lines := source.split("\n")
	var in_add_participant_row := false
	var in_add_ai_count_row := false
	var hbox_count := 0

	for line in lines:
		if "func _add_participant_row" in line:
			in_add_participant_row = true
			in_add_ai_count_row = false
		elif "func _add_ai_count_row" in line:
			in_add_ai_count_row = true
			in_add_participant_row = false
		elif line.begins_with("func "):
			in_add_participant_row = false
			in_add_ai_count_row = false

		if (in_add_participant_row or in_add_ai_count_row) and "HBoxContainer.new()" in line:
			hbox_count += 1

	assert_eq(hbox_count, 0, "no HBoxContainer.new() calls in the two row builders")
