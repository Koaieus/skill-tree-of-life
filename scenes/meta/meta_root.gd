extends Control

## Entry point for the meta/menu flow: splash -> main menu -> (singleplayer
## -> lobby -> START) / options. Persistent single scene (see MenuStack) so
## breadcrumb ancestors stay alive instead of being destroyed by a scene
## swap. The only SceneDirector.goto() in this flow is lobby START -> the
## actual game level.

const FIRST_LEVEL_SANDBOX := preload("res://scenes/first_level_sandbox.tscn")

@onready var _splash: SplashScreen = %Splash
@onready var _stack: MenuStack = %MenuStack


func _ready() -> void:
	_stack.visible = false
	_splash.advanced.connect(_on_splash_advanced)
	_stack.emptied.connect(_on_stack_emptied)


func _on_splash_advanced() -> void:
	_splash.visible = false
	_stack.visible = true
	_show_main_menu()


func _on_stack_emptied() -> void:
	_stack.visible = false
	_splash.visible = true


func _show_main_menu() -> void:
	var main := MainMenuScreen.new()
	main.single_player_pressed.connect(_on_single_player_pressed)
	main.multiplayer_pressed.connect(_on_multiplayer_pressed)
	main.options_pressed.connect(_on_options_pressed)
	main.quit_pressed.connect(func(): get_tree().quit())
	_stack.push(main)


func _on_single_player_pressed() -> void:
	var singleplayer := SingleplayerMenuScreen.new()
	singleplayer.new_game_pressed.connect(_on_new_game_pressed)
	_stack.push(singleplayer)


func _on_multiplayer_pressed() -> void:
	# #456 LAN milestone scaffolding: straight to a 2-local-human hot-seat
	# lobby, no intermediate screen. Actual peer join/leave is #463.
	var lobby := LobbyScreen.new()
	lobby.configure(RunConfig.Mode.COOP_HOTSEAT)
	lobby.start_pressed.connect(_on_start_pressed)
	_stack.push(lobby)


func _on_options_pressed() -> void:
	_stack.push(OptionsMenuScreen.new())


func _on_new_game_pressed() -> void:
	var lobby := LobbyScreen.new()
	lobby.configure(RunConfig.Mode.SINGLE)
	lobby.start_pressed.connect(_on_start_pressed)
	_stack.push(lobby)


## START opens the run before the level loads (#457): `GameSession.start`
## resolves the lobby's seed sentinel once, here, and the level reads the
## concrete value back out. `RunConfig.level_scene` is still unread — picking
## a level from the lobby is future work; every run is the first-level sandbox.
func _on_start_pressed(run_config: RunConfig) -> void:
	GameSession.start(run_config)
	SceneDirector.goto(FIRST_LEVEL_SANDBOX)
