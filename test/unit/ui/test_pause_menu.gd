extends GutTest

## The pause menu's two wired-up exits and the global fullscreen key.
##
## `_on_to_main_menu_button_pressed` itself is deliberately NOT driven here: it
## ends in [method SceneDirector.goto], which would swap the scene out from
## under the whole test run. What it delegates to ([method PauseMenu.leave_run])
## and where it points ([constant PauseMenu.MAIN_MENU_SCENE]) are both testable,
## and together they are the whole button.

const _PAUSE_MENU := preload("res://ui/pause_menu.tscn")

var _menu: PauseMenu
var _prev_window_mode: int


func before_each() -> void:
	_prev_window_mode = Settings.current.window_mode
	_menu = _PAUSE_MENU.instantiate()
	add_child_autofree(_menu)


func after_each() -> void:
	Settings.current.window_mode = _prev_window_mode
	get_tree().paused = false
	GameSession.end()


# --- MAIN MENU ---------------------------------------------------------------

## `application/run/main_scene` is stored as a `uid://`, not a path, so this
## resolves it rather than comparing strings.
func test_main_menu_button_targets_the_scene_the_game_boots_into() -> void:
	var boot: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if boot.begins_with("uid://"):
		boot = ResourceUID.get_id_path(ResourceUID.text_to_id(boot))
	assert_eq(GameRoot.META_ROOT, boot,
			"MAIN MENU must go where an exported build boots")


func test_main_menu_target_scene_exists() -> void:
	assert_true(ResourceLoader.exists(GameRoot.META_ROOT),
			"%s is not loadable" % GameRoot.META_ROOT)


## Unpausing is not cosmetic: SceneTransition is a PAUSABLE autoload, so a
## `goto` issued from a frozen tree would await a fade that never finishes.
func test_leaving_a_run_unpauses_before_the_scene_change() -> void:
	_menu.active = true
	assert_true(get_tree().paused, "sanity: the menu paused the tree")

	_menu.leave_run()

	assert_false(get_tree().paused, "the tree must be running before goto")
	assert_false(_menu.active)
	assert_false(_menu.visible)


func test_leaving_a_run_closes_the_session() -> void:
	var cfg := RunConfig.new()
	cfg.seed = 1234
	GameSession.start(cfg)
	assert_true(GameSession.is_active(), "sanity: a run is live")

	_menu.leave_run()

	assert_false(GameSession.is_active(), "the abandoned run must not stay live")
	assert_null(GameSession.network, "a stale NetworkConfig would re-open a socket")


func test_unimplemented_buttons_are_disabled_rather_than_warning() -> void:
	for name in ["SaveButton", "LoadButton"]:
		var button: Button = _menu.find_child(name, true, false)
		assert_not_null(button, "%s went missing" % name)
		if button != null:
			assert_true(button.disabled, "%s must be disabled while unimplemented" % name)


# --- FULLSCREEN --------------------------------------------------------------

func test_fullscreen_action_is_bound_to_f() -> void:
	assert_true(InputMap.has_action(&"ui_toggle_fullscreen"))
	var bound := false
	for event in InputMap.action_get_events(&"ui_toggle_fullscreen"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_F:
			bound = true
	assert_true(bound, "F must be the physical key for ui_toggle_fullscreen")


func test_toggle_fullscreen_round_trips_through_the_setting() -> void:
	Settings.current.window_mode = GameSettings.WindowMode.WINDOWED

	Settings.toggle_fullscreen()
	assert_eq(Settings.current.window_mode, GameSettings.WindowMode.FULLSCREEN)

	Settings.toggle_fullscreen()
	assert_eq(Settings.current.window_mode, GameSettings.WindowMode.WINDOWED)


## The whole reason the previous mode is remembered rather than assumed.
func test_toggle_fullscreen_returns_to_borderless_not_windowed() -> void:
	Settings.current.window_mode = GameSettings.WindowMode.BORDERLESS

	Settings.toggle_fullscreen()
	assert_eq(Settings.current.window_mode, GameSettings.WindowMode.FULLSCREEN)

	Settings.toggle_fullscreen()
	assert_eq(Settings.current.window_mode, GameSettings.WindowMode.BORDERLESS)


## The one test that proves the feature rather than a piece of it: every other
## fullscreen assert here would still pass if an autoload never received
## unhandled key input at all. No display needed — the setting is what moves,
## and `_apply_display_settings` no-ops headless.
func test_pressing_f_reaches_the_autoload_and_toggles() -> void:
	Settings.current.window_mode = GameSettings.WindowMode.WINDOWED

	var press := InputEventKey.new()
	press.physical_keycode = KEY_F
	press.pressed = true
	get_tree().root.push_input(press)

	assert_eq(Settings.current.window_mode, GameSettings.WindowMode.FULLSCREEN,
			"F must reach Settings._unhandled_key_input")


func test_fullscreen_key_survives_a_paused_tree() -> void:
	assert_eq(Settings.process_mode, Node.PROCESS_MODE_ALWAYS,
			"a PAUSABLE Settings would stop hearing F the moment the game pauses")
