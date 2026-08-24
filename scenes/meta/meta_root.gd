extends Control

## Entry point for the meta/menu flow: splash -> the frontmatter skill tree ->
## a leaf's panel -> START. The only [method SceneDirector.goto] in this flow is
## the lobby's START, into the actual game level.
##
## [b]This file is the ROUTING and nothing else.[/b] Since #579 the presentation
## belongs to [FrontmatterRoot] — one persistent menu graph and a camera — and
## what survives here is exactly the set of decisions that were never about
## presentation: which [NetworkConfig] a route leaves on [GameSession], which
## peer this machine is before a socket opens, and when a run actually starts.
## `test/unit/ui/test_meta_routing_parity.gd` pins all three against this file.
##
## [b]The breadcrumb is gone.[/b] There is no [Control] stack of screens any
## more; "where am I" is [member FrontmatterRoot.focus_id] and going back is
## [method FrontmatterRoot.back], which under a moving camera is the same call
## as going forward (#567). Nothing here tracks a history.

const FIRST_LEVEL_SANDBOX := preload("res://scenes/first_level_sandbox.tscn")

@onready var _splash: SplashScreen = %Splash
@onready var _frontmatter: FrontmatterRoot = %Frontmatter


func _ready() -> void:
	_frontmatter.visible = false
	_splash.advanced.connect(_on_splash_advanced)
	_bind_panels()
	_frontmatter.focus_changed.connect(_on_focus_changed)


func _on_splash_advanced() -> void:
	_splash.visible = false
	_frontmatter.visible = true


## Wires the two panels that produce something this file has to act on. The
## other three (settings, load, exit confirm) are answered entirely inside the
## panel layer — the exit confirm's quit goes to [FrontmatterRoot], which owns
## the tree, not here.
func _bind_panels() -> void:
	var lobby := _lobby_panel()
	if lobby != null:
		lobby.start_pressed.connect(_on_start_pressed)
	var join := _join_panel()
	if join != null:
		join.join_requested.connect(_on_join_requested)
		join.host_requested.connect(_on_host_requested)
		join.hotseat_requested.connect(_on_hotseat_requested)


## Arriving on a leaf that authors a run is what used to be a button press.
##
## Only the leaves whose panel IS the lobby route from here: JOIN opens the
## code-entry panel first and reaches the lobby through
## [method _on_join_requested] once an address has been typed. That asymmetry is
## #531's, restated — it is the reason [MenuGraph.Item] splits "which panel
## opens" from "what run shape does this eventually author".
func _on_focus_changed(id: StringName) -> void:
	var item := _frontmatter.tree.get_item(id)
	if item == null or item.route == null:
		return
	if item.panel != MenuGraph.PANEL_LOBBY:
		return
	_push_lobby(item.route.requested_mode, _network_for(item.route))


## The [NetworkConfig] constructor a route's role names. Every role is spelled
## out, including OFFLINE — see [method _push_lobby] for why that matters.
static func _network_for(route: MenuGraph.Route) -> NetworkConfig:
	match route.network_role:
		NetworkTransport.Role.HOST:
			return NetworkConfig.host()
		NetworkTransport.Role.CLIENT:
			return NetworkConfig.join(NetworkConfig.DEFAULT_ADDRESS)
		_:
			return NetworkConfig.offline()


## The mode passed here is the shape this ROUTE asks for, not the mode the run
## gets: #554 D3 derives that from the roster when START is pressed
## ([method LobbyScreen.resolve_mode]), because "more than one non-AI camp" is
## not knowable at the moment a route is taken. Host and Join both end up
## VERSUS by way of the remote seat their lobby authors; hot-seat stays coop
## because its two humans share a camp.
func _on_host_requested(port: int) -> void:
	_push_lobby(RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.host(port))


func _on_join_requested(address: String, port: int) -> void:
	_push_lobby(RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.join(address, port))


func _on_hotseat_requested() -> void:
	_push_lobby(RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.offline())


## Every route into the lobby goes through here, so the role is stated on ALL
## of them — including the offline ones. Being explicit is what stops a player
## who hosted, backed out, and started a solo game from silently opening a
## socket on the way in: [method GameSession.end] clears the role when a run
## finishes, and this re-states it when one begins.
func _push_lobby(mode: RunConfig.Mode, network: NetworkConfig) -> void:
	GameSession.network = network
	var lobby := _lobby_panel()
	if lobby == null:
		return
	lobby.configure(mode, network)
	var panels := _panels()
	if panels != null:
		panels.show_panel(MenuGraph.PANEL_LOBBY)


## START opens the run before the level loads (#457): `GameSession.start`
## resolves the lobby's seed sentinel once, here, and the level reads the
## concrete value back out. `RunConfig.level_scene` is still unread — picking
## a level from the lobby is future work; every run is the first-level sandbox.
func _on_start_pressed(run_config: RunConfig) -> void:
	GameSession.start(run_config)
	_stamp_local_peer()
	SceneDirector.goto(FIRST_LEVEL_SANDBOX)


## Which peer THIS machine is, before any socket opens.
##
## A host is always id 1 under Godot's high-level multiplayer, so it is
## knowable here — and it has to be, because the level generates from the
## roster and derives its [SeatPolicy] before a peer has connected. A CLIENT
## cannot know its own id until the link is up, so it stays 0 here and
## [GameRoot] stamps it from the transport when the link comes up.
static func _stamp_local_peer() -> void:
	var net: NetworkConfig = GameSession.network
	GameSession.local_peer_id = (NetworkTransport.HOST_PEER_ID
			if net != null and net.role == NetworkTransport.Role.HOST
			else 0)


## Found by type rather than by path. `%PanelLayer` is unique-named inside
## `frontmatter_root.tscn`, and a `%` name resolves against the scene that owns
## it — so it is reachable from [FrontmatterRoot] and not from here, one scene
## up. Searching by class keeps this file out of the frontmatter's internals,
## which #573/#579 split deliberately: C6 owns the panels, C3 owns the shell.
func _panels() -> FrontmatterPanels:
	var found := _frontmatter.find_children("*", "FrontmatterPanels", true, false)
	return null if found.is_empty() else found[0] as FrontmatterPanels


func _lobby_panel() -> LobbyPanel:
	var panels := _panels()
	return null if panels == null else panels.get_panel(MenuGraph.PANEL_LOBBY) as LobbyPanel


func _join_panel() -> JoinPanel:
	var panels := _panels()
	return null if panels == null else panels.get_panel(MenuGraph.PANEL_JOIN) as JoinPanel
