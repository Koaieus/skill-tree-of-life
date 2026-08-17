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
	main.options_pressed.connect(_on_options_pressed)
	main.quit_pressed.connect(func(): get_tree().quit())
	_stack.push(main)


func _on_single_player_pressed() -> void:
	var singleplayer := SingleplayerMenuScreen.new()
	singleplayer.new_game_pressed.connect(_on_new_game_pressed)
	_stack.push(singleplayer)


func _on_options_pressed() -> void:
	_stack.push(OptionsMenuScreen.new())


func _on_new_game_pressed() -> void:
	var lobby := LobbyScreen.new()
	lobby.start_pressed.connect(_on_start_pressed)
	_stack.push(lobby)


## `_seed_text` is intentionally unread — wiring the seed into procgen is
## future work (see LobbyScreen); this just starts the sandbox level.
func _on_start_pressed(_seed_text: String) -> void:
	SceneDirector.goto(FIRST_LEVEL_SANDBOX)
