extends GutTest

## #463 V1 — a joining client plays the HOST's run, not its own.
##
## Before this, both machines pressed their own START, each resolved its own
## seed, each generated its own map, and the socket only came up afterwards:
## `CommandLink._on_run_setup` handed the host's [RunConfig] to
## [method GameSession.apply_received] and nothing in `scenes/` consumed the
## [signal GameSession.run_started] that came back out. Two lobbies configured
## identically genuinely played each other; anything else desynced in silence,
## which is what `HostJoinScreen`'s retired "both players must type the same
## seed" caption was honestly disclaiming.
##
## The adoption is two halves and this file covers both:
## 1. [method GameRoot.await_host_run] — the level does not generate until the
##    host's `run_setup` has landed, so the seed AND the roster it builds from
##    are the host's. Covered by [method test_a_client_that_typed_a_different_seed_plays_the_hosts_run].
## 2. [method GameRoot.pull_host_world] — the client then asks for the
##    authority's SERIALIZED world and reconciles onto it, because generating
##    from a shared seed is not the same as playing the same map (#547:
##    `procgen/` leans on transcendentals whose last bit is not portable across
##    two platforms' libm). Owner, 2026-08-22: [i]"serializing the graph is the
##    best way forward... a non-pristine graph could still be sent"[/i].
##
## [b]The client here starts from a genuinely DIFFERENT world[/b] — its own
## procgen run at its own seed and its own node count, not an empty graph. That
## is the case the acceptance spec names, and it is the one
## [method GraphSnapshot.decode]'s #561 reconcile contract exists for.
##
## [b]Two worlds in one process[/b], with the same accepted hazards
## `test_mp_procgen_join.gd` documents at length: nothing dies here, and every
## spawn goes through [method _spawn_scoped] so `Entity._find_turn_manager`'s
## tree-wide group lookup can only see the spawning world's own TurnManager.
##
## [b]GameSession is a singleton autoload[/b], so this file plays both machines
## against one instance — the host's config is captured into a local before
## [method CommandLink._on_run_setup] overwrites it with the client's decoded
## reading, exactly as a second OS process would receive it into its own.

const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")
const _RED_COLOR := Color(0.4, 0.8, 1.0)
const _BLUE_COLOR := Color(0.95, 0.4, 0.4)

## The host resolved this. The client typed the other one, and must end up
## playing this one regardless.
const _HOST_SEED := 90210463
const _CLIENT_TYPED_SEED := 11223344

## Deliberately different node counts as well as different seeds: a client that
## merely rolled different CONTENT would still converge by accident if the
## reconcile only repaired ownership, so the two worlds differ in topology too.
const _HOST_NODES := 60
const _CLIENT_NODES := 45

var _host_root: GameRoot
var _client_root: GameRoot
var _host_config: RunConfig
var _host_roster: ParticipantRoster


func before_each() -> void:
	GameSession.end()
	GameSession.network = null
	GameSession.local_peer_id = 0


func after_each() -> void:
	GameSession.end()
	GameSession.network = null
	GameSession.local_peer_id = 0


func _build_root(label: String) -> GameRoot:
	var root: GameRoot = preload("res://scenes/game_root.tscn").instantiate()
	root.name = "GameRoot_%s" % label
	root.auto_start_turn = false
	add_child_autofree(root)
	return root


## See `test_mp_procgen_join.gd`'s note: hides every OTHER world's TurnManager
## from the group for the duration of one spawn.
func _spawn_scoped(root: GameRoot, ent_name: String, color: Color,
		core_location: SkillNode, core_class: CoreClass) -> Entity:
	var hidden: Array[Node] = []
	for other in get_tree().get_nodes_in_group(TurnManager.GROUP):
		if other != root.turn_manager:
			hidden.append(other)
			other.remove_from_group(TurnManager.GROUP)
	var ent := root.spawn_entity(ent_name, color, core_location, core_class)
	for other in hidden:
		other.add_to_group(TurnManager.GROUP)
	return ent


## Two HUMANS on opposing camps, one per machine — the versus shape, so
## "which seat is mine" has a wrong answer available to get wrong. Red sits at
## the host (peer 1), Blue at the joining client (peer 2, the id
## [LoopbackTransport] mints for a paired client).
func _versus_roster() -> ParticipantRoster:
	var roster := ParticipantRoster.new()
	var red := Participant.new()
	red.id = 1
	red.display_name = "Red"
	red.color = _RED_COLOR
	red.camp = _PLAYER_FACTION
	red.kind = Participant.Kind.HUMAN
	red.peer_id = NetworkTransport.HOST_PEER_ID
	roster.add(red)
	var blue := Participant.new()
	blue.id = 2
	blue.display_name = "Blue"
	blue.color = _BLUE_COLOR
	blue.camp = _NPC_FACTION
	blue.kind = Participant.Kind.HUMAN
	blue.peer_id = _CLIENT_PEER_ID
	roster.add(blue)
	return roster


## What `LoopbackTransport.pair()` mints for the joining end, and what a real
## ENet client would learn from `transport.local_peer_id()` in
## [method GameRoot._on_peer_joined]. Restated rather than read because the
## transport's own constant is private.
const _CLIENT_PEER_ID := 2


func _generate(root: GameRoot, run_seed: int, node_count: int) -> Array:
	var gcfg: GraphProcgenConfig = _PRESET.duplicate(true)
	# #349: `topology` is a top-level module .tres (ExtResource) and does not
	# cross `duplicate(true)` — re-duplicate before mutating.
	gcfg.topology = gcfg.topology.duplicate(true)
	gcfg.topology.node_count = node_count
	gcfg.n_random_starters = 1
	gcfg.seed = run_seed
	var result: Dictionary = await GraphProcgen.generate(gcfg, root.graph)
	return result.get("starting_nodes", [])


## Builds the two machines up to the moment the client's socket comes up:
## a host with a real generated world, and a client holding a DIFFERENT world
## generated from the seed its own lobby collected. Nothing has crossed the
## wire yet.
func _two_divergent_worlds() -> void:
	_host_root = _build_root("host")
	_client_root = _build_root("client")
	await wait_physics_frames(2)

	var host_transport := _host_root.transport as LoopbackTransport
	var client_transport := _client_root.transport as LoopbackTransport
	host_transport.peer = client_transport
	client_transport.peer = host_transport
	host_transport.role = NetworkTransport.Role.HOST
	client_transport.role = NetworkTransport.Role.CLIENT
	host_transport.my_peer_id = NetworkTransport.HOST_PEER_ID
	client_transport.my_peer_id = _CLIENT_PEER_ID
	_host_root.command_link.mode = CommandLink.Mode.BROADCAST
	_client_root.command_link.mode = CommandLink.Mode.MIRROR

	# HOST: the run it decided.
	var host_cfg := RunConfig.new()
	host_cfg.seed = _HOST_SEED
	GameSession.start(host_cfg)
	_host_roster = _versus_roster()
	GameSession.roster = _host_roster
	var host_starts := await _generate(_host_root, _HOST_SEED, _HOST_NODES)
	assert_eq(host_starts.size(), 2, "sanity: 1 authored + 1 random starter (host)")
	var host_red := _spawn_scoped(_host_root, "Red", _RED_COLOR, host_starts[0], _BALANCED)
	var host_blue := _spawn_scoped(_host_root, "Blue", _BLUE_COLOR, host_starts[1], _BALANCED)
	GameRoot.apply_roster({1: host_red, 2: host_blue}, _host_roster)
	# Captured before the client's own START, and before `_on_run_setup`,
	# overwrite the shared singleton — see the class docstring.
	_host_config = host_cfg

	# CLIENT: the run it *thought* it was starting. A different seed and a
	# different size, generated and populated exactly as a level would have
	# done before the host said anything.
	var client_cfg := RunConfig.new()
	client_cfg.seed = _CLIENT_TYPED_SEED
	GameSession.start(client_cfg)
	var client_starts := await _generate(_client_root, _CLIENT_TYPED_SEED, _CLIENT_NODES)
	assert_eq(client_starts.size(), 2, "sanity: 1 authored + 1 random starter (client)")
	var client_red := _spawn_scoped(_client_root, "Red", _RED_COLOR, client_starts[0], _BALANCED)
	var client_blue := _spawn_scoped(_client_root, "Blue", _BLUE_COLOR, client_starts[1], _BALANCED)
	assert_eq(client_red.entity_id, host_red.entity_id, "sanity: minting order matched")
	assert_eq(client_blue.entity_id, host_blue.entity_id, "sanity: minting order matched")

	# What `GameRoot._on_peer_joined` does on the CLIENT side: the server mints
	# the id, so this is the first moment the joining machine knows its own.
	GameSession.local_peer_id = client_transport.local_peer_id()
	# And what it does on the HOST side — the run's shape, and only that.
	_host_root.command_link.send_run_setup(_host_config, _host_roster)


## The run the client is now holding is the host's, not the one it typed —
## acceptance 1, at the settings layer. The `_CLIENT_NODES` world it generated
## is still on screen at this point; the next test is what replaces it.
func test_a_client_that_typed_a_different_seed_plays_the_hosts_run() -> void:
	await _two_divergent_worlds()

	assert_eq(GameSession.config.seed, _HOST_SEED,
			"the seed this machine typed (%d) must lose to the host's" % _CLIENT_TYPED_SEED)
	assert_ne(GameSession.config.seed, _CLIENT_TYPED_SEED,
			"a client that keeps its own seed is the defect #463 opened on")
	assert_eq(GameSession.roster.all().size(), _host_roster.all().size(),
			"the roster is the host's too — a join lobby is offered no AI-count row, "
			+ "so a client that kept its own would spawn a different entity SET")


## Acceptance 2. The client asked for the authority's world and reconciled onto
## it, from a genuinely different map — different seed AND different node count.
func test_the_worlds_converge_once_the_client_pulls_the_hosts() -> void:
	await _two_divergent_worlds()

	var host_fingerprint := WorldFingerprint.compute(_host_root.graph)
	assert_ne(WorldFingerprint.compute(_client_root.graph), host_fingerprint,
			"sanity: the two worlds really did start out different")

	# The one line `GameRoot._ready` runs at the tail on a joining machine.
	# `_is_network_client` reads GameSession.network, which only the client has
	# by now — the host root finished its own `_ready` before this was set.
	GameSession.network = _client_network()
	_client_root.pull_host_world()
	await get_tree().process_frame

	assert_eq(WorldFingerprint.compute(_client_root.graph), host_fingerprint,
			"ownership + topology + HP must match once the client has adopted")
	assert_eq(_client_root.graph.get_skill_nodes().size(), _HOST_NODES,
			"the client's own %d-node map must be gone, not merged into" % _CLIENT_NODES)


## Acceptance 3 — the client adopts the host's WORLD without adopting the
## host's SEAT. Both machines run the same roster; each answers "which of these
## is mine" from its own [member GameSession.local_peer_id], which is exactly
## the axis `docs/domain/seat-policy.md` says may differ between peers.
func test_the_client_is_seated_on_its_own_participant_after_adopting() -> void:
	await _two_divergent_worlds()
	GameSession.network = _client_network()
	_client_root.pull_host_world()
	await get_tree().process_frame

	var client_red := _client_root.graph.get_by_entity_id(1)
	var client_blue := _client_root.graph.get_by_entity_id(2)
	assert_not_null(client_red, "sanity: Red survived the reconcile")
	assert_not_null(client_blue, "sanity: Blue survived the reconcile")
	# `core_location` rides EntitySnapshot's pass 2 (#560), which the resync
	# envelope runs after the graph half — so a seat that resolves also proves
	# the client is pointing at a hero that has a core on the NEW map.
	assert_not_null(client_blue.core_location, "the seated hero has a core on the host's map")
	assert_eq(client_blue.core_location.owned_by, client_blue)

	var seat := SeatPolicy.from_roster(
			{1: client_red, 2: client_blue}, GameSession.roster, GameSession.local_peer_id)
	assert_eq(seat.seating, SeatPolicy.Seating.SEAT, "a peer behind a wire is pinned, not a couch")
	assert_true(seat.seats(client_blue), "this machine plays Blue — its own lobby seat")
	assert_false(seat.seats(client_red), "it must NOT adopt the host's hero along with the host's map")

	# And the host reads the same roster the other way round, from its own id.
	var host_seat := SeatPolicy.from_roster(
			{1: _host_root.graph.get_by_entity_id(1), 2: _host_root.graph.get_by_entity_id(2)},
			GameSession.roster, NetworkTransport.HOST_PEER_ID)
	assert_ne(host_seat.seated_entity_id, seat.seated_entity_id,
			"the two machines are seated on different heroes — the WANTED difference")


## [method GameRoot.await_host_run] is a no-op for everyone who is not adopting
## a run: the host, and every offline launch. That is what keeps single-player
## and hot-seat on the untouched pre-#463 path rather than hanging on a signal
## nobody will emit.
func test_await_host_run_is_inert_off_the_join_path() -> void:
	var root := _build_root("offline")
	await wait_physics_frames(1)
	GameSession.network = null
	await root.await_host_run()
	assert_true(true, "returned rather than hanging with no network config")

	GameSession.network = _host_network()
	await root.await_host_run()
	assert_true(true, "returned rather than hanging as the HOST")


## The invariant the moved `_open_link` depends on, made executable.
##
## A client now opens its socket BEFORE `_setup_level`, so there is a window on
## the joining side where the link is up and the world is not — or, as here, is
## still the wrong one. Nothing buffers that traffic:
## [method CommandApplier.apply_remote] enqueues and drains at once, against
## whatever world is present. When the ids do not resolve, `_validate` warns and
## drops. When they DO resolve against the wrong world — which is what happens
## below, and why no warning appears in the log — the command lands on whatever
## node happens to carry that `stable_id`, silently. The quiet case is the
## dangerous one, and it is the case this test pins.
##
## [b]That is survivable only because the pull comes after.[/b] The resync
## carries every effect of every command the window swallowed, and
## `EnetTransport._receive` is an `@rpc(..., "reliable")` — ordered as well as
## delivered — so anything the host applies after encoding the reply is sent
## after the envelope and lands on top of it. This test is what fails if
## `pull_host_world` is ever moved later in `_ready` than the line where the
## world first exists.
func test_a_command_that_lands_before_the_pull_cannot_outlive_it() -> void:
	await _two_divergent_worlds()

	# The host plays on while the joining machine is still catching up. On the
	# client this mirrors into a world whose `stable_id`s mean something else
	# entirely — the case the old `_open_link` placement existed to prevent.
	var host_red: Entity = _host_root.graph.get_by_entity_id(1)
	var target := _first_frontier_node(_host_root.graph, host_red)
	assert_not_null(target, "sanity: Red has somewhere to expand")
	_host_root.command_applier.submit(AllocateCommand.new(
			host_red.entity_id, _host_root.graph.get_stable_id(target)))
	await get_tree().process_frame

	var host_fingerprint := WorldFingerprint.compute(_host_root.graph)
	assert_ne(WorldFingerprint.compute(_client_root.graph), host_fingerprint,
			"sanity: mirroring a command into the wrong world does not converge it — "
			+ "whether it dropped or landed on the wrong node, the peers still disagree")

	GameSession.network = _client_network()
	_client_root.pull_host_world()
	await get_tree().process_frame

	assert_eq(WorldFingerprint.compute(_client_root.graph), host_fingerprint,
			"the pull supersedes the window's outcome, whatever it was")
	assert_eq(target.owned_by, host_red, "sanity: the host really did allocate it")
	var client_target := _client_root.graph.get_by_stable_id(
			_host_root.graph.get_stable_id(target))
	assert_not_null(client_target, "the allocated node exists on the client after the pull")
	assert_eq(client_target.owned_by, _client_root.graph.get_by_entity_id(1),
			"and it is owned by Red there too")


## An unowned node adjacent to [param red]'s territory — the cheapest legal
## `AllocateCommand` target.
func _first_frontier_node(graph: Graph, red: Entity) -> SkillNode:
	for node in graph.get_skill_nodes():
		if node.owned_by != null:
			continue
		for neighbour in graph.get_neighbours(node):
			if neighbour.owned_by == red:
				return node
	return null


func _client_network() -> NetworkConfig:
	return NetworkConfig.join(NetworkConfig.DEFAULT_ADDRESS)


func _host_network() -> NetworkConfig:
	return NetworkConfig.host()
