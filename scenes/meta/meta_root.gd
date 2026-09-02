extends Control

## Entry point for the meta/menu flow: the attract state -> the frontmatter
## skill tree -> a leaf's panel -> START. The only [method SceneDirector.goto] in this flow is
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

## Fallback destination (#641 acceptance 4/5) for a route whose composed
## [RunConfig] carries no [Scenario] at all — today, every route:
## [LobbyScreen.build_run_config] does not yet author one, so this constant is
## still what every lobby-launched run reaches. The BARE level (#584) — no
## [RunBootstrap], so it has no way to start a run of its own and generates
## only from the session the lobby already opened.
## `scenes/first_level_sandbox.tscn` is the same scene plus an authored run,
## and is an editor-launch convenience that nothing routes to.
const FIRST_LEVEL_SANDBOX := preload("res://scenes/level.tscn")

@onready var _frontmatter: FrontmatterRoot = %Frontmatter


## The frontmatter is visible from the first frame — since #574 the splash is
## the same picture zoomed in on the root node, not a curtain in front of it, so
## there is nothing here to show or hide. [SplashScreen] parks the camera and
## takes itself off screen when it advances; this file only routes.
func _ready() -> void:
	_bind_panels()
	_frontmatter.focus_started.connect(_on_focus_started)
	# #715 acceptance 6: a CLIENT learns its own id the instant the socket
	# connects — which is now in the LOBBY, long before a level exists. This is
	# the same routing decision the rest of this file makes ("which peer is this
	# machine"), so it stays here. [LobbyScreen] asks its own transport the same
	# question for its own rows; what this connection settles is the value the
	# RUN carries, which is [GameSession]'s and nobody else's.
	#
	# Through an INSTANCE method rather than `_stamp_local_peer.unbind(1)`: the
	# subscriber is the `Wire` autoload, which outlives this scene, and a static
	# Callable is not owned by this node — so Godot's free-time auto-disconnect
	# would not fire and the connection would pile up on every route back to the
	# menu. `unbind(1)` could not be disconnected by hand either
	# (`.claude/rules/gdscript-pitfalls.md`).
	Wire.peer_joined.connect(_on_wire_peer_joined)
	_drive_lobby_from_cmdline()


## Wires the three panels that produce something this file has to act on. The
## other three (settings, load, exit confirm) are answered entirely inside the
## panel layer — the exit confirm's quit goes to [FrontmatterRoot], which owns
## the tree, not here.
func _bind_panels() -> void:
	var lobby := _lobby_panel()
	if lobby != null:
		lobby.start_pressed.connect(_on_start_pressed)
		# #715: the same destination, reached from the wire. A joiner has no
		# button to press — the host's START is what routes it.
		lobby.remote_start.connect(_on_remote_start)
	var join := _join_panel()
	if join != null:
		join.join_requested.connect(_on_join_requested)
	var host := _host_panel()
	if host != null:
		host.host_requested.connect(_on_host_requested)
	# #716 item 2: the lobby's back button. Its sibling route out — a focus
	# change to some other leaf — is caught in [method _on_focus_started].
	var panels := _panels()
	if panels != null:
		panels.panel_dismissed.connect(_on_panel_dismissed)


## Taking a route to a leaf that authors a run is what used to be a button
## press.
##
## [b]On [signal FrontmatterRoot.focus_started], not `focus_changed`.[/b] Since
## the panel slides in from [member FrontmatterRoot.panel_lead] rather than on
## arrival, a lobby configured on ARRIVAL was configured too late: the two
## offline leaves share ONE lobby panel, so going back and walking into the
## other one slid the previous route's roster on screen and only swapped its
## contents when the camera finally stopped. Content is pushed at departure —
## before the panel can be raised at all — which is the general rule for
## anything that fills a panel: be ready before the reveal clock starts, never
## when it ends.
##
## Only the leaves whose panel IS the lobby route from here — today the two
## offline ones. HOST and JOIN each open a config panel first and reach the
## lobby through [method _on_host_requested] / [method _on_join_requested] once
## a port (and, for JOIN, an address) has been typed. That asymmetry is #531's,
## widened by #582 — it is the reason [MenuGraph.Item] splits "which panel
## opens" from "what run shape does this eventually author".
## [b]Leaving is routed here too (#716 item 2).[/b] Every navigation in the
## frontmatter goes through [method FrontmatterRoot.focus], which emits this — so
## a focus that is not a lobby leaf IS the back-out, whether the player pressed
## the panel's back button or walked into a different leaf entirely. Stating it
## as "anything that is not the lobby" rather than enumerating the ways out is
## what stops the next route from silently keeping a socket open.
##
## HOST and JOIN focus their own config panel and only swap the LOBBY panel in
## afterwards, without moving the focus — so on those routes the leaving edge is
## the focus change off that same leaf, which this still catches.
func _on_focus_started(id: StringName) -> void:
	var item := _frontmatter.tree.get_item(id)
	if item == null or item.panel != MenuGraph.PANEL_LOBBY:
		_leave_lobby()
		return
	if item.route == null:
		return
	_push_lobby(item.route.requested_mode, _network_for(item.route),
			item.route.lobby_policy)


func _on_panel_dismissed(id: StringName) -> void:
	if id == MenuGraph.PANEL_LOBBY:
		_leave_lobby()


## Backing out of a lobby is a leave, and a leave stops the socket (#716
## acceptance 3). Before this, a host that opened a listener and walked away kept
## it — nothing released [LobbyScreen]'s bound link but START — and the next Host
## click bound a port this machine already held.
##
## Idempotent by construction: both are no-ops when there is nothing open, which
## is what lets every route out call it without asking whether it was in a lobby.
static func _leave_lobby() -> void:
	GameSession.network = null
	Wire.stop()


## The [NetworkConfig] constructor a route's role names. Every role is spelled
## out, including OFFLINE — see [method _push_lobby] for why that matters.
##
## Only the OFFLINE branch is reached today: since #582 both networked roles
## arrive through a panel that already typed their digits, and a role reaching a
## lobby WITHOUT them would be exactly the "hosts on the default port forever"
## bug that issue was filed about. The match stays total all the same, so a
## future lobby-routed role fails loudly rather than silently coming out
## offline.
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
	_push_lobby(RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.host(port),
			_policy_of(MenuGraph.ID_HOST))


func _on_join_requested(address: String, port: int) -> void:
	_push_lobby(RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.join(address, port),
			_policy_of(MenuGraph.ID_JOIN))


## The [LobbyPolicy] a leaf authored (#615 D2). HOST and JOIN reach the lobby
## through their config panel rather than through their own focus change, so
## they cannot read `item.route` off it — they ask for it by id here.
## Read from the tree rather than restated as a constant so there stays exactly
## one authoring site; a null answer is legal and means "today's behaviour".
func _policy_of(id: StringName) -> LobbyPolicy:
	if _frontmatter == null or _frontmatter.tree == null:
		return null
	var item := _frontmatter.tree.get_item(id)
	return null if item == null or item.route == null else item.route.lobby_policy


## Every route into the lobby goes through here, so the role is stated on ALL
## of them — including the offline ones. Being explicit is what stops a player
## who hosted, backed out, and started a solo game from silently opening a
## socket on the way in: [method GameSession.end] clears the role when a run
## finishes, and this re-states it when one begins.
func _push_lobby(
	mode: RunConfig.Mode, network: NetworkConfig, policy: LobbyPolicy = null
) -> void:
	GameSession.network = network
	_open_wire_for(network)
	var lobby := _lobby_panel()
	if lobby == null:
		return
	lobby.configure(mode, network, policy)
	var panels := _panels()
	if panels != null:
		panels.show_panel(MenuGraph.PANEL_LOBBY)


## Bring the wire up for the route being taken, or take it down (#714).
##
## [b]This file, because the decision is the same one it already makes.[/b] The
## role a route leaves on [GameSession] and whether that role means a socket are
## one fact stated twice; splitting them across two files is how a player who
## hosted, backed out and started a solo game ends up still listening on 9099.
## Since #713 the socket lives on [Wire] and outlives every scene, so "take it
## down when the route goes offline" is a thing that has to be said out loud.
##
## [b]Opening it HERE, and not in the lobby, is what keeps the lobby honest.[/b]
## [LobbyScreen] adopts a live link and mounts nothing when there isn't one, so
## every offline lobby — and every existing lobby test — is on exactly the path
## it was on before.
##
## [b]It always (re)opens on the endpoint that was typed (#716).[/b] There used
## to be a "same role, leave it alone" shortcut here, and it compared ROLES —
## so re-hosting on a different port was a silent no-op and the player kept
## listening on the old one. Since every route into [method _push_lobby] now
## passes through [method _leave_lobby] on the way out of the previous one, there
## is no live link left to preserve anyway: the case the shortcut existed for
## cannot arise, and the case it broke was real.
static func _open_wire_for(net: NetworkConfig) -> void:
	Wire.stop()
	if net == null or not net.is_online():
		return
	if net.role == NetworkTransport.Role.HOST:
		Wire.start_host(net.port)
	else:
		Wire.start_client(net.address, net.port)


## START opens the run before the level loads (#457): `GameSession.start`
## resolves the lobby's seed sentinel once, here, and the level reads the
## concrete value back out. [method _destination_for] decides where.
##
## [b]That one call is also the broadcast (#715).[/b] `GameSession.start` emits
## [signal GameSession.run_started], and a lobby holding a live link answers it
## by shipping the now-resolved [RunConfig] + [ParticipantRoster] down the wire
## and handing its link back ([method LobbyScreen._on_run_started]). Which is
## why the order on these three lines is load-bearing and not incidental: the
## peer must have the run before this machine leaves the menu, and the seed must
## be resolved before the peer has it. Nothing is pushed on JOIN any more —
## a pre-established link never fires that signal again.
func _on_start_pressed(run_config: RunConfig) -> void:
	GameSession.start(run_config)
	_stamp_local_peer()
	SceneDirector.goto(_destination_for(run_config))


## The joiner's half of the same moment (#715). The run is ALREADY open here —
## [method GameSession.apply_received] adopted the host's config when the
## broadcast landed on the lobby's link — so this deliberately does not call
## [method GameSession.start]: re-opening the run would re-resolve the seed and
## hand this machine a different run than the one it was invited to.
func _on_remote_start(run_config: RunConfig) -> void:
	_stamp_local_peer()
	SceneDirector.goto(_destination_for(run_config))


func _on_wire_peer_joined(_peer_id: int) -> void:
	_stamp_local_peer()


## The destination a run's [Scenario] names (#641 acceptance 4) — a run whose
## `scenario` carries a [member Scenario.level_scene] routes there; one with no
## `scenario` at all (every route today — [LobbyScreen.build_run_config] does
## not yet author one, since picking a Scenario from the lobby is future work)
## or a `scenario` with no `level_scene` falls back to
## [constant FIRST_LEVEL_SANDBOX].
##
## `static`, same reason [method _stamp_local_peer] already is: a test can call
## it directly rather than driving the whole frontmatter tree to prove the
## reader moved with the field (#584 D5).
static func _destination_for(run_config: RunConfig) -> PackedScene:
	var scenario: Scenario = run_config.scenario
	if scenario != null and scenario.level_scene != null:
		return scenario.level_scene
	return FIRST_LEVEL_SANDBOX


## Which peer THIS machine is — asked of the socket, which since #713 exists
## before any level does and since #714 is opened by this very file on the way
## into the lobby.
##
## [b]The `0` this used to hard-code for a client is gone (#715 acceptance 6),
## and so is the comment that justified it.[/b] "Before any socket opens" stopped
## being true the moment the lobby got a live link: a joiner learns its own
## server-minted id at `connected_to_server`, while the menu is still up, and
## every seat the lobby draws — which row reads "you", which pickers it may
## touch — turns on that id. So this runs at two moments, both of them before
## the level exists: on [signal Wire.peer_joined] (the id arriving) and at START
## (the id being carried into the run).
##
## [method Wire.local_peer_id] answers all three cases on its own, which is why
## there is no role branch left here: `1` on a host (ENet's server id, and
## knowable before anyone connects — the level derives its [SeatPolicy] from the
## roster before a peer exists), the minted id on a connected client, and `0`
## with no socket at all, which is the [member Participant.peer_id] an offline
## lobby authors. A client that has not connected YET is also `0`, and stays a
## couch by construction until it does. [method GameRoot._on_peer_joined] still
## re-stamps, for the client whose dial only completes once the level exists.
static func _stamp_local_peer() -> void:
	GameSession.local_peer_id = Wire.local_peer_id()


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


func _host_panel() -> HostPanel:
	var panels := _panels()
	return null if panels == null else panels.get_panel(MenuGraph.PANEL_HOST) as HostPanel


# --- Rung 3: the lobby, driven from the command line (#715) --------------------
#
#   godot --headless --path . -- --lobby=host --port=9300
#   godot --headless --path . -- --lobby=client --address=127.0.0.1 --port=9300
#
# Two OS processes driving the REAL menu route — no scene argument, nothing
# stubbed. What it proves, why it is on `turn_started`, and why both halves read
# nothing without the flag: `docs/domain/multiplayer-harness.md`, "Rung 3".
const _RUNG3_FLAG := "--lobby="


func _drive_lobby_from_cmdline() -> void:
	var role := ""
	var address := NetworkConfig.DEFAULT_ADDRESS
	var port := NetworkConfig.DEFAULT_PORT
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		if pair.size() != 2:
			continue
		match pair[0]:
			"lobby":
				role = pair[1]
			"address":
				address = pair[1]
			"port":
				port = int(pair[1])
	if role.is_empty():
		return
	print("[%s] rung 3: driving the lobby from the command line" % role)
	if role == "host":
		_on_host_requested(port)
		# The host presses START once a human has actually arrived — which is the
		# whole thing under test: the seat was authored up front so procgen could
		# see it, and only its identity was outstanding.
		Wire.peer_joined.connect(_press_start_when_seated, CONNECT_ONE_SHOT)
	else:
		_on_join_requested(address, port)


## One deferred hop so [method LobbyScreen._on_link_peer_joined] has stamped the
## waiting seat before START reads the roster off it.
func _press_start_when_seated(_peer_id: int) -> void:
	await get_tree().process_frame
	var lobby := _lobby_panel()
	if lobby == null or lobby.screen == null:
		push_error("rung 3: no lobby to start")
		return
	print("[host] rung 3: peer seated — pressing START")
	lobby.screen._on_start_button_pressed()
