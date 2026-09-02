extends GutTest

## #715 — the joining client stops building a world of its own.
##
## Until this, a client generated the whole map from the host's seed and then
## pulled the authority's serialized world on top of it: 5-10 seconds spent on a
## map it was about to throw away, and a window in which the link was up and a
## WRONG world was present. It now builds nothing. `_setup_level` seats the
## roster and returns; [method GameRoot.pull_host_world] brings the world.
##
## [b]"Never runs procgen" is asserted on the OUTCOME of not running it[/b]
## (acceptance 2). [GraphProcgen] is a static pipeline with no seam to spy on, so
## what is pinned is the only thing a generate call could not leave behind: a
## graph with zero [SkillNode]s after `_setup_level` has returned. A run that
## generated and then somehow emptied itself is not a failure mode this codebase
## has — `generate` adds nodes and nothing removes them all.
##
## [b]The entities are still spawned, and that is the half that may not be
## dropped.[/b] [EntitySnapshot] decorates by `entity_id` and the roster's seats
## must exist before the host's state arrives, in the SAME order, or every row is
## skipped. So the client's `_setup_level` is "spawn the roster, generate
## nothing".

const _LEVEL := preload("res://scenes/level.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

## What a lobby-seated versus run looks like on the wire: the host's hero and
## this machine's, on opposing camps.
const _HOST_PEER := 1
const _CLIENT_PEER := 2


## `Wire.stop()` on both sides, and it is not housekeeping. A joined level mounts
## the shipped [EnetTransport] and `_open_link` really does dial — nothing is
## listening, so it never connects, but `multiplayer.multiplayer_peer` is
## SceneTree-global and an [ENetMultiplayerPeer] left in that slot changes what
## `multiplayer.get_unique_id()` answers for every test that runs after this one
## (`test_intent_channel.gd` mints its ids from it). [method Wire.stop] puts the
## [OfflineMultiplayerPeer] back.
func before_each() -> void:
	GameSession.end()
	GameSession.network = null
	GameSession.local_peer_id = 0
	Wire.stop()


func after_each() -> void:
	GameSession.end()
	GameSession.network = null
	GameSession.local_peer_id = 0
	Wire.stop()


func _versus_roster() -> ParticipantRoster:
	var roster := ParticipantRoster.new()
	for spec in [[1, "Red", _PLAYER_FACTION, _HOST_PEER], [2, "Blue", _NPC_FACTION, _CLIENT_PEER]]:
		var p := Participant.new()
		p.id = int(spec[0])
		p.display_name = String(spec[1])
		p.camp = spec[2] as Faction
		p.kind = Participant.Kind.HUMAN
		p.peer_id = int(spec[3])
		roster.add(p)
	return roster


## Opens the run exactly as the lobby leaves it on a machine that JOINED: the
## host's resolved config already adopted, this machine's own peer id stamped.
func _open_joined_run() -> void:
	var cfg := RunConfig.new()
	cfg.seed = 90210715
	GameSession.apply_received(cfg, _versus_roster())
	GameSession.network = NetworkConfig.join(NetworkConfig.DEFAULT_ADDRESS)
	GameSession.local_peer_id = _CLIENT_PEER


## The shipped level, on the machine that joined. `show_ui` off and
## `auto_start_turn` off keep this a `_setup_level` test rather than a HUD one;
## the transport is the scene's [EnetTransport] with no socket behind it, which
## announces itself and links to nobody.
func _build_joined_level() -> GameRoot:
	var root: GameRoot = _LEVEL.instantiate()
	root.name = "JoinedLevel"
	root.show_ui = false
	root.auto_start_turn = false
	root.enable_fog = false
	add_child_autofree(root)
	return root


## Acceptance 2, and the whole point of the unit: no map is built here.
func test_a_joined_level_generates_no_graph_at_all() -> void:
	_open_joined_run()
	var root := _build_joined_level()
	await wait_physics_frames(3)

	assert_eq(root.graph.get_skill_nodes().size(), 0,
			"a joining client must not run procgen — every node here is one it "
			+ "spent wall-clock on and is about to throw away")
	assert_eq(root.graph.get_edges().size(), 0, "and no edges either")


## The other half: it DOES seat the roster, in roster order, so `entity_id`
## minting lands on the host's numbers and [EntitySnapshot] has something to
## decorate.
func test_a_joined_level_still_spawns_the_rosters_entities() -> void:
	_open_joined_run()
	var root := _build_joined_level()
	await wait_physics_frames(3)

	var entities := EntitySnapshot.entities_of(root.graph)
	assert_eq(entities.size(), 2, "one entity per roster seat, and no blockers")
	assert_eq(entities[0].entity_id, 1, "ids mint by add-order — the host's numbers")
	assert_eq(entities[1].entity_id, 2)
	for e in entities:
		assert_null(e.core_location,
				"no nodes exist yet to allocate onto; the snapshot's pass 2 resolves it")


## Acceptance 4, at the level rather than at a hand-built dictionary: this
## machine is SEATed on its own lobby seat, not on the host's hero.
func test_the_joined_level_seats_this_machines_own_participant() -> void:
	_open_joined_run()
	var root := _build_joined_level()
	await wait_physics_frames(3)

	assert_eq(root.seat_policy.seating, SeatPolicy.Seating.SEAT,
			"a peer behind a wire is pinned, never a couch")
	assert_eq(root.seat_policy.seated_entity_id, 2,
			"participant 2 is the one sitting at peer %d" % _CLIENT_PEER)
	assert_not_null(root.player, "and it is bound as this machine's player")


## Acceptance 5: the 30-second hang is gone because the method that caused it is.
##
## `await_host_run` blocked `_setup_level` on [signal GameSession.run_started].
## Once START broadcasts the run in the LOBBY, that signal has already fired by
## the time a level exists — so the level awaited something that would never come
## again and [constant SceneDirector.REVEAL_TIMEOUT_S] caught it. Leaving the
## method in place was a half-minute hang, not dead code.
func test_await_host_run_is_gone() -> void:
	var root: GameRoot = preload("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(root)
	assert_false(root.has_method("await_host_run"),
			"a level that waits for a run setup waits forever now — the run is "
			+ "already adopted before the level loads")


## Acceptance 5, the consequence — and the ONE thing a joined level still waits
## for, which is not a `run_setup`.
##
## `_ready` runs all the way to `pull_host_world` without blocking: the run is
## already adopted, so there is no handshake left to miss. What it then waits on
## is the WORLD — arming [VictorySystem], starting a turn or lifting the curtain
## over an empty graph is not "a bit early", it is a level with no map. There is
## no socket behind this fixture, so the reply never comes and the level
## correctly never reveals; [SceneDirector]'s 30s timeout is the backstop for
## exactly that, and on a live link (harness rung 3) the world lands in seconds.
func test_a_joined_level_waits_for_the_world_and_nothing_else() -> void:
	_open_joined_run()
	var root := _build_joined_level()
	await wait_physics_frames(3)

	assert_false(root.is_reveal_ready(),
			"no world has arrived, so there is nothing worth revealing")
	assert_true(root.command_link.defer_until_resync,
			"and it is the RESYNC it is waiting on — #667's latch, still armed")
	assert_gt(EntitySnapshot.entities_of(root.graph).size(), 0,
			"`_setup_level` itself ran to completion: it did not block on a run setup")


## Acceptance 8, restated where it can regress: an OFFLINE run still generates.
## The client branch sits behind `_is_network_client`, so a run with no
## [NetworkConfig] must take the untouched path.
func test_an_offline_run_still_generates_locally() -> void:
	var cfg := RunConfig.new()
	cfg.seed = 90210715
	var roster := _versus_roster()
	for p in roster.all():
		p.peer_id = 0
	cfg.participants = roster.all()
	GameSession.start(cfg)
	GameSession.network = NetworkConfig.offline()

	var root: GameRoot = _LEVEL.instantiate()
	root.name = "OfflineLevel"
	root.show_ui = false
	root.auto_start_turn = false
	root.enable_fog = false
	root.node_count_override = 40
	add_child_autofree(root)
	# Procgen yields across frames; the level's `_ready` is a coroutine.
	for _i in 400:
		if not root.graph.get_skill_nodes().is_empty() and root.is_reveal_ready():
			break
		await get_tree().process_frame

	assert_gt(root.graph.get_skill_nodes().size(), 0,
			"an offline run is untouched by #715 and builds its own map")
	assert_not_null(root.player, "and seats a local player as it always did")
