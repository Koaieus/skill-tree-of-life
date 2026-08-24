extends GutTest

## The frontmatter's panel layer (#573) — the seam the navigation state machine
## calls, and the three panels that carry no run state.
##
## [b]What this pins is the seam, not the pixels.[/b] #567's testing contract
## puts glow, easing and "does it look good" on the sandbox tab and the owner's
## eye; what is decidable in code is which panel is up, that exactly one is, and
## that dismissing one hands the stage back to the graph. So every assertion
## below is about [FrontmatterPanels]' four public calls and the one signal C3
## consumes.
##
## The lobby and join panels are absent on purpose — they are held pending the
## orchestrator's call on the routing-parity collision (see this unit's report);
## nothing here presumes their shape.

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


func test_the_panels_that_carry_no_run_state_are_registered() -> void:
	assert_true(_panels.has_panel(MenuGraph.PANEL_SETTINGS))
	assert_true(_panels.has_panel(MenuGraph.PANEL_LOAD))
	assert_true(_panels.has_panel(MenuGraph.PANEL_EXIT_CONFIRM))


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
	# There is no stack. #567 replaced MenuStack's breadcrumb with the graph
	# itself, so two panels up at once would be the old shape creeping back.
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
	# calls SceneTree.quit — the same split meta_root.gd ships for
	# MainMenuScreen.quit_pressed today.
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
