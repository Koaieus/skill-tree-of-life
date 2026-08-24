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


## #531 put a screen between this signal and the lobby: Multiplayer now asks
## HOW before it asks what. All three answers land on the same lobby — what
## differs is the [NetworkConfig], and since #554 that is also what decides the
## lobby's roster shape (a networked lobby seats a REMOTE_HUMAN, a hot-seat one
## seats two locals on one camp).
func _on_multiplayer_pressed() -> void:
	var screen := HostJoinScreen.new()
	screen.host_pressed.connect(_on_host_pressed)
	screen.join_pressed.connect(_on_join_pressed)
	screen.hotseat_pressed.connect(_on_hotseat_pressed)
	_stack.push(screen)


## The mode passed here is the shape this ROUTE asks for, not the mode the run
## gets: #554 D3 derives that from the roster when START is pressed
## ([method LobbyScreen.resolve_mode]), because "more than one non-AI camp" is
## not knowable at the moment a button is pressed. Host and Join both end up
## VERSUS by way of the remote seat their lobby authors; hot-seat stays coop
## because its two humans share a camp.
func _on_host_pressed(port: int) -> void:
	_push_lobby(RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.host(port))


func _on_join_pressed(address: String, port: int) -> void:
	_push_lobby(RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.join(address, port))


func _on_hotseat_pressed() -> void:
	_push_lobby(RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.offline())


func _on_options_pressed() -> void:
	_stack.push(OptionsMenuScreen.new())


func _on_new_game_pressed() -> void:
	_push_lobby(RunConfig.Mode.SINGLE, NetworkConfig.offline())


## Every route into the lobby goes through here, so the role is stated on ALL
## of them — including the offline ones. Being explicit is what stops a player
## who hosted, backed out, and started a solo game from silently opening a
## socket on the way in: [method GameSession.end] clears the role when a run
## finishes, and this re-states it when one begins.
func _push_lobby(mode: RunConfig.Mode, network: NetworkConfig) -> void:
	GameSession.network = network
	var lobby := LobbyScreen.new()
	lobby.configure(mode, network)
	lobby.start_pressed.connect(_on_start_pressed)
	_stack.push(lobby)


## START opens the run before the level loads (#457): `GameSession.start`
## resolves the lobby's seed sentinel once, here, and the level reads the
## concrete value back out. `RunConfig.level_scene` is still unread — picking
## a level from the lobby is future work; every run is the first-level sandbox.
func _on_start_pressed(run_config: RunConfig) -> void:
	GameSession.start(run_config)
	_seat_roster(run_config)
	SceneDirector.goto(FIRST_LEVEL_SANDBOX)


## Move the lobby's authored participants onto the live session (#554).
##
## [method GameSession.start] deliberately opens an EMPTY roster — it takes a
## [RunConfig], and a roster is runtime state, not authored data. Until this
## call existed, nothing bridged the two, so every menu-launched run arrived at
## `procgen_play_sandbox` with an empty roster and fell into that level's
## FALLBACK shape: one local human and one NPC camp, whatever the lobby said.
## The bridge lives here rather than inside `start` because this is the only
## caller that has a lobby behind it — a directly-launched sandbox's
## [method GameSession.ensure_started] must keep getting an empty roster, which
## is the signal that tells it to invent its own.
##
## Goes through [method ParticipantRoster.add] one at a time so
## `participant_joined` fires per participant, exactly as it does for one that
## arrives over the wire.
static func _seat_roster(run_config: RunConfig) -> void:
	if GameSession.roster == null:
		GameSession.roster = ParticipantRoster.new()
	for participant in run_config.participants:
		GameSession.roster.add(participant)
	# Which peer THIS machine is. A host is always id 1 under Godot's
	# high-level multiplayer, so it is knowable here, before any socket opens —
	# and it has to be, since the level generates from the roster before a peer
	# has connected. A CLIENT cannot know its own id until the link is up, so it
	# stays 0 here and the transport stamps it at level start.
	var net: NetworkConfig = GameSession.network
	if net != null and net.role == NetworkTransport.Role.HOST:
		GameSession.local_peer_id = NetworkTransport.HOST_PEER_ID
	else:
		GameSession.local_peer_id = 0
