extends GutTest

## Keyboard and gamepad navigation over the menu graph (#576).
##
## Events are synthesized and fed to [method FrontmatterInput._handle] rather
## than pumped through a viewport: that method IS the input contract, and going
## through `Input.parse_input_event` would be testing Godot's dispatch instead of
## this file's decisions. The events themselves are real
## [InputEventKey] / [InputEventJoypadButton] instances matched against the real
## `ui_*` actions, so a broken action binding still shows up here.

const _INPUT := preload("res://ui/frontmatter/frontmatter_input.gd")
const _FRONTMATTER := preload("res://ui/frontmatter/frontmatter_root.tscn")
const _SPLASH := preload("res://ui/frontmatter/splash_screen.tscn")

var _frontmatter: FrontmatterRoot
var _input: FrontmatterInput


func before_each() -> void:
	_frontmatter = _FRONTMATTER.instantiate()
	add_child_autofree(_frontmatter)
	_frontmatter.reduce_motion = true
	_input = _INPUT.new()
	add_child_autofree(_input)
	_input.bind(_frontmatter)


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	return event


func _pad(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	return event


func _send(event: InputEvent) -> bool:
	return _input._handle(event)


func _options() -> Array[StringName]:
	return _frontmatter.tree.children_of(_frontmatter.focus_id)


# --- the cursor is not the focus ---------------------------------------------

func test_the_cursor_starts_on_the_first_option_of_the_fan() -> void:
	assert_eq(_frontmatter.focus_id, _frontmatter.tree.root)
	assert_eq(_input.cursor, MenuGraph.ID_SINGLE_PLAYER)


func test_moving_the_cursor_does_not_move_the_camera() -> void:
	# The distinction the whole file rests on: looking at an option is not
	# choosing it. If these ever merge, merely scrolling the fan navigates.
	var before := _frontmatter.focus_id
	_send(_key(KEY_DOWN))
	assert_eq(_input.cursor, MenuGraph.ID_MULTIPLAYER)
	assert_eq(_frontmatter.focus_id, before, "the camera has not moved")


func test_the_cursor_reseats_when_the_focus_changes() -> void:
	_send(_key(KEY_ENTER))  # commit to Single Player
	assert_eq(_frontmatter.focus_id, MenuGraph.ID_SINGLE_PLAYER)
	assert_eq(_input.cursor, MenuGraph.ID_NEW_GAME, "seated on the new fan")


func test_a_leaf_leaves_the_cursor_nowhere() -> void:
	_frontmatter.focus(MenuGraph.ID_OPTIONS, true)
	assert_eq(_input.cursor, &"", "a leaf has no fan to pick from")


# --- up and down --------------------------------------------------------------

func test_down_steps_forward_through_the_siblings() -> void:
	_send(_key(KEY_DOWN))
	assert_eq(_input.cursor, MenuGraph.ID_MULTIPLAYER)
	_send(_key(KEY_DOWN))
	assert_eq(_input.cursor, MenuGraph.ID_OPTIONS)


func test_up_steps_backward() -> void:
	_send(_key(KEY_DOWN))
	_send(_key(KEY_UP))
	assert_eq(_input.cursor, MenuGraph.ID_SINGLE_PLAYER)


func test_down_at_the_last_sibling_WRAPS_to_the_first() -> void:
	# #576 allows wrap or clamp but demands one be pinned. WRAP, because a fan is
	# two to four items and a clamped last `ui_down` reads as a dropped input.
	var options := _options()
	for i in options.size() - 1:
		_send(_key(KEY_DOWN))
	assert_eq(_input.cursor, options[options.size() - 1], "at the last option")

	_send(_key(KEY_DOWN))
	assert_eq(_input.cursor, options[0], "wraps to the first")


func test_up_at_the_first_sibling_WRAPS_to_the_last() -> void:
	var options := _options()
	assert_eq(_input.cursor, options[0], "starts at the first")

	_send(_key(KEY_UP))
	assert_eq(_input.cursor, options[options.size() - 1], "wraps to the last")


# --- keyboard focus counts as hover ------------------------------------------

func test_the_cursor_raises_the_same_peek_the_mouse_would() -> void:
	# #576 forbids inventing a seventh ring colour and asks for an existing focus
	# treatment to be reused. This is that reuse — and it is why a keyboard
	# player can see what a commit would do before making it. Asserted through
	# the tooltip, which `set_hovered` binds.
	_send(_key(KEY_DOWN))
	var tooltip := _frontmatter.find_children("*", "MenuTooltip", true, false)
	assert_false(tooltip.is_empty(), "the frontmatter has a tooltip to raise")
	assert_true((tooltip[0] as Node).visible,
			"moving the cursor onto Multiplayer describes it")


# --- committing ---------------------------------------------------------------

func test_accept_commits_to_the_cursor() -> void:
	_send(_key(KEY_DOWN))
	_send(_key(KEY_ENTER))
	assert_eq(_frontmatter.focus_id, MenuGraph.ID_MULTIPLAYER)


func test_right_commits_too() -> void:
	_send(_key(KEY_RIGHT))
	assert_eq(_frontmatter.focus_id, MenuGraph.ID_SINGLE_PLAYER)


func test_a_disabled_option_is_refused_rather_than_followed() -> void:
	# LOAD GAME, while #23 is parked. The press is CONSUMED — letting it fall
	# through would make a refused commit read as a back.
	_send(_key(KEY_ENTER))  # into Single Player
	_send(_key(KEY_DOWN))   # onto Load Game
	assert_eq(_input.cursor, MenuGraph.ID_LOAD_GAME)

	var handled := _send(_key(KEY_ENTER))
	assert_true(handled, "the press did something — it refused")
	assert_eq(_frontmatter.focus_id, MenuGraph.ID_SINGLE_PLAYER, "and did not navigate")


# --- going back ---------------------------------------------------------------

func test_cancel_goes_back_up() -> void:
	_send(_key(KEY_ENTER))
	assert_eq(_frontmatter.focus_id, MenuGraph.ID_SINGLE_PLAYER)

	_send(_key(KEY_ESCAPE))
	assert_eq(_frontmatter.focus_id, _frontmatter.tree.root)


func test_left_goes_back_too() -> void:
	_send(_key(KEY_ENTER))
	_send(_key(KEY_LEFT))
	assert_eq(_frontmatter.focus_id, _frontmatter.tree.root)


func test_cancel_at_the_root_is_a_no_op_but_is_still_consumed() -> void:
	# A no-op that reported "not handled" would let `ui_cancel` fall through to
	# whatever sits behind the menu.
	var handled := _send(_key(KEY_ESCAPE))
	assert_true(handled)
	assert_eq(_frontmatter.focus_id, _frontmatter.tree.root)


# --- the panel layer ----------------------------------------------------------

func _open_settings() -> FrontmatterPanels:
	_frontmatter.focus(MenuGraph.ID_OPTIONS, true)
	var found := _frontmatter.find_children("*", "FrontmatterPanels", true, false)
	return found[0] as FrontmatterPanels


func test_committing_to_a_panel_leaf_raises_its_panel() -> void:
	var panels := _open_settings()
	assert_eq(panels.shown_panel, MenuGraph.PANEL_SETTINGS)


func test_a_raised_panel_owns_up_and_down() -> void:
	# Its own Controls handle those. Reporting "not handled" is what lets the
	# focused Button in the panel see the event at all.
	_open_settings()
	assert_false(_send(_key(KEY_DOWN)), "the panel gets it, not the graph")
	assert_false(_send(_key(KEY_ENTER)), "same for accept")


func test_cancel_inside_a_panel_returns_to_the_graph() -> void:
	var panels := _open_settings()

	var handled := _send(_key(KEY_ESCAPE))

	assert_true(handled)
	assert_eq(panels.shown_panel, &"", "the panel let go of the stage")
	assert_eq(_frontmatter.focus_id, _frontmatter.tree.root,
			"and the graph went back up, exactly as a clicked back button would")


func test_the_panel_takes_the_keyboard_when_it_is_raised() -> void:
	# A controller player must not be left with a lit-up panel and no way in.
	var panels := _open_settings()
	var panel := panels.get_panel(MenuGraph.PANEL_SETTINGS)
	assert_true(panel.back_button.has_focus(), "the way out is focused")


# --- gamepad ------------------------------------------------------------------

func test_a_gamepad_can_move_the_cursor() -> void:
	_send(_pad(JOY_BUTTON_DPAD_DOWN))
	assert_eq(_input.cursor, MenuGraph.ID_MULTIPLAYER)


func test_a_gamepad_can_commit_and_go_back() -> void:
	_send(_pad(JOY_BUTTON_A))
	assert_eq(_frontmatter.focus_id, MenuGraph.ID_SINGLE_PLAYER)

	_send(_pad(JOY_BUTTON_B))
	assert_eq(_frontmatter.focus_id, _frontmatter.tree.root)


# --- the splash accepts a gamepad too -----------------------------------------

func test_a_joypad_button_advances_the_splash() -> void:
	# #576: it says "PRESS ANY BUTTON" and shipped handling key + mouse only, so
	# a controller player was stuck on the title screen.
	var splash: SplashScreen = _SPLASH.instantiate()
	splash.frontmatter_path = _frontmatter.get_path()
	add_child_autofree(splash)

	assert_true(SplashScreen.is_any_button(_pad(JOY_BUTTON_START)))
	assert_true(SplashScreen.is_any_button(_key(KEY_SPACE)))


func test_a_released_button_is_not_a_press() -> void:
	var released := _pad(JOY_BUTTON_A)
	released.pressed = false
	assert_false(SplashScreen.is_any_button(released))


func test_mouse_motion_is_not_a_button() -> void:
	assert_false(SplashScreen.is_any_button(InputEventMouseMotion.new()))


func test_the_dpad_commits_and_goes_back_through_the_real_action_map() -> void:
	# The path that works WITHOUT this file's face-button stopgap: ui_right and
	# ui_left do carry D-pad bindings in this project, so a controller could
	# always walk the menu. Pinned separately from the A/B test so that deleting
	# the stopgap (once project.godot binds the face buttons) cannot silently
	# take this with it.
	_send(_pad(JOY_BUTTON_DPAD_RIGHT))
	assert_eq(_frontmatter.focus_id, MenuGraph.ID_SINGLE_PLAYER)

	_send(_pad(JOY_BUTTON_DPAD_LEFT))
	assert_eq(_frontmatter.focus_id, _frontmatter.tree.root)


func test_the_face_buttons_are_a_stopgap_the_action_map_does_not_cover() -> void:
	# Probed 2026-08-25: ui_accept is Enter/Kp Enter/Space and ui_cancel is
	# Escape — neither carries a joypad event, which is why FrontmatterInput
	# checks the face buttons itself. If this assertion ever FAILS, the project
	# input map has grown the bindings and JOY_ACCEPT/JOY_CANCEL can be deleted.
	for action in [&"ui_accept", &"ui_cancel"]:
		for event in InputMap.action_get_events(action):
			assert_false(event is InputEventJoypadButton,
					"'%s' now binds a joypad button — retire the stopgap" % action)


# --- mid-flight: the cursor may never outlive its fan ------------------------

## These run with the transitions ON, which is why they were missing: every
## other test in this file sets `reduce_motion = true` in `before_each`, and a
## menu that arrives in the same frame it sets off has no window in which the
## cursor can go stale.
func _travelling() -> void:
	_frontmatter.reduce_motion = false
	_frontmatter.travel_duration = 0.85


func test_the_cursor_reseats_when_the_camera_sets_off_not_when_it_arrives() -> void:
	_travelling()
	_send(_key(KEY_RIGHT))  # commit to Single Player, camera now travelling
	assert_eq(_frontmatter.focus_id, MenuGraph.ID_SINGLE_PLAYER, "focus is already there")
	assert_eq(_input.cursor, MenuGraph.ID_NEW_GAME, "and so is the cursor, mid-flight")


func test_back_then_forward_mid_flight_does_not_skip_a_level() -> void:
	# The shipped bug, exactly (#576 follow-up). The cursor was seated on
	# `focus_changed`, which fires on ARRIVAL, so for the whole 850ms of travel
	# it still named a child of the node being left behind: pressing `ui_left`
	# and then `ui_right` committed to a GRANDCHILD of the node the camera had
	# just returned to.
	_travelling()
	_frontmatter.focus(MenuGraph.ID_SINGLE_PLAYER, true)
	assert_eq(_input.cursor, MenuGraph.ID_NEW_GAME)

	_send(_key(KEY_LEFT))
	assert_eq(_frontmatter.focus_id, MenuGraph.ID_ROOT, "heading back to the root")
	assert_eq(_input.cursor, MenuGraph.ID_SINGLE_PLAYER, "on the root's fan already")

	_send(_key(KEY_RIGHT))
	assert_eq(
		_frontmatter.focus_id, MenuGraph.ID_SINGLE_PLAYER,
		"forward from the root is one level, not two"
	)


func test_stepping_mid_flight_walks_the_fan_being_travelled_to() -> void:
	_travelling()
	_send(_key(KEY_RIGHT))  # to Single Player, mid-flight
	_send(_key(KEY_DOWN))
	assert_eq(_input.cursor, MenuGraph.ID_LOAD_GAME, "the new fan, not the old one")
