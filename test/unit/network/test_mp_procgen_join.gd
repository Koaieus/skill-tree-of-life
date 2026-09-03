extends GutTest

## Rung 2 of the multiplayer harness (#533): a joining peer receives its run
## settings (#528, [method CommandLink.send_run_setup]), its graph (#527,
## [method CommandLink.send_graph_snapshot]) and its entity state (#560,
## [method CommandLink.send_entity_snapshot]) instead of re-deriving any of
## it locally. See docs/domain/multiplayer-harness.md's "Rung 2" section, and
## #547's comment on #533 for why re-deriving from a shared seed is unsafe —
## `procgen/` leans on transcendentals whose last bit is not IEEE-754-portable
## across platforms' libm, so two peers "typing the same seed" can silently
## generate different maps.
##
## Drives two REAL `game_root.tscn` instances in one process, paired through
## their own already-mounted [LoopbackTransport] (#531's mounted default) —
## NOT `scenes/dev/mp_procgen_sandbox.tscn` itself, which additionally needs a
## real socket and two OS processes to prove anything; that half is exercised
## manually via the Multiplayer tab, the same division rung 1's own test
## coverage makes (`test_harness_budget_boost.gd` tests `build_args`, not a
## spawned process).
##
## [b]Two worlds in one process, same accepted hazard as
## test_command_link.gd.[/b] Nothing here kills anything, so the death/loot/
## victory cross-wiring that rules this out elsewhere never fires. The OTHER
## tree-wide lookup that file warns about — `Entity._find_turn_manager` via
## `get_first_node_in_group(TurnManager.GROUP)` — DOES apply here: every spawn
## below goes through [method _spawn_scoped], hiding every other world's
## TurnManager while an entity binds, exactly like that file's `_build_world`.
##
## [b]GameSession is a singleton autoload[/b] — this file plays BOTH machines
## in one process, so the host's config is captured into a local BEFORE
## [method CommandLink._on_run_setup] (triggered synchronously by
## [method CommandLink.send_run_setup] over a loopback) overwrites the shared
## instance with the CLIENT's decoded reading, exactly as a second real
## process would receive it into its own separate instance.

const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _BASIC_ENEMY := preload("res://entity/core/basic_enemy_core.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")
const _RED_COLOR := Color(0.4, 0.8, 1.0)
const _BLUE_COLOR := Color(0.95, 0.4, 0.4)
const _FIXED_SEED := 90210533

var _host_root: GameRoot
var _client_root: GameRoot


func before_each() -> void:
	GameSession.end()


func after_each() -> void:
	GameSession.end()


func _build_root(label: String) -> GameRoot:
	var root: GameRoot = preload("res://scenes/game_root.tscn").instantiate()
	root.name = "GameRoot_%s" % label
	root.auto_start_turn = false
	add_child_autofree(root)
	return root


## See the class docstring's tree-wide-lookup note: hides every OTHER world's
## TurnManager from the group for the duration of one spawn, so
## `Entity._find_turn_manager` can only find the spawning world's own.
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


func _fixed_roster() -> ParticipantRoster:
	var roster := ParticipantRoster.new()
	var red := Participant.new()
	red.id = 0
	red.display_name = "Red"
	red.color = _RED_COLOR
	red.camp = _PLAYER_FACTION
	red.kind = Participant.Kind.HUMAN
	roster.add(red)
	var blue := Participant.new()
	blue.id = 1
	blue.display_name = "Blue"
	blue.color = _BLUE_COLOR
	blue.camp = _NPC_FACTION
	blue.kind = Participant.Kind.AI
	roster.add(blue)
	return roster


## HOST procgens a small level + a fixed 2-participant roster, spawns Red and
## Blue, then sends run_setup followed by a graph snapshot. CLIENT spawns bare
## placeholders FIRST, in the same order (so `entity_id` minting matches),
## then decodes. Returns a Dictionary a test can assert against.
func _join() -> Dictionary:
	_host_root = _build_root("host")
	_client_root = _build_root("client")
	await wait_physics_frames(2)

	var host_transport := _host_root.transport as LoopbackTransport
	var client_transport := _client_root.transport as LoopbackTransport
	host_transport.peer = client_transport
	client_transport.peer = host_transport
	host_transport.role = NetworkTransport.Role.HOST
	client_transport.role = NetworkTransport.Role.CLIENT
	_host_root.command_link.mode = CommandLink.Mode.BROADCAST
	_client_root.command_link.mode = CommandLink.Mode.MIRROR

	# HOST: procgen a small level from a fixed, already-resolved seed.
	var cfg := RunConfig.new()
	cfg.seed = _FIXED_SEED
	GameSession.start(cfg)
	var gcfg: GraphProcgenConfig = _PRESET.duplicate(true)
	# #349: topology is a top-level module .tres (ExtResource); duplicate(true)
	# does not cross that boundary, so re-duplicate before mutating (acceptance 4).
	gcfg.topology = gcfg.topology.duplicate(true)
	gcfg.topology.node_count = 60
	gcfg.camp_sizes = [2]
	gcfg.seed = GameSession.config.seed
	var result: Dictionary = await GraphProcgen.generate(gcfg, _host_root.graph)
	var starting_nodes: Array = result.get("starting_nodes", [])
	assert_eq(starting_nodes.size(), 2, "sanity: 1 authored + 1 random starter")

	var roster := _fixed_roster()
	GameSession.roster = roster
	var red := _spawn_scoped(_host_root, "Red", _RED_COLOR, starting_nodes[0], _BALANCED)
	var blue := _spawn_scoped(_host_root, "Blue", _BLUE_COLOR, starting_nodes[1], _BASIC_ENEMY)
	GameRoot.apply_roster({0: red, 1: blue}, roster)

	# Captured before `apply_received` overwrites the shared GameSession
	# singleton with the CLIENT's decoded reading (see the class docstring).
	var host_config_dict := GameSession.config.to_dict()

	# CLIENT: no procgen (#547) — placeholders in the SAME order, so Graph's
	# per-entry entity_id minting lands on the host's numbers. No
	# core_location: no graph exists yet to allocate onto.
	var client_red := _spawn_scoped(_client_root, "Red", _RED_COLOR, null, _BALANCED)
	var client_blue := _spawn_scoped(_client_root, "Blue", _BLUE_COLOR, null, _BASIC_ENEMY)
	assert_eq(client_red.entity_id, red.entity_id, "sanity: minting order matched")
	assert_eq(client_blue.entity_id, blue.entity_id, "sanity: minting order matched")

	_host_root.command_link.send_run_setup(GameSession.config, GameSession.roster)
	assert_eq(GameSession.config.to_dict(), host_config_dict,
			"sanity: sending must not mutate the host's own config")
	# #560: the ENTITY half of the join, sent BEFORE the graph — its own
	# class docstring's documented order (pass 1 needs no SkillNode and runs
	# before GraphSnapshot.decode; pass 2, entity → node, runs after). Decodes
	# the already-spawned placeholders (never mints) and is what resolves
	# `core_location`, the opposite direction from GraphSnapshot's
	# `owner_id` → entity.
	_host_root.command_link.send_entity_snapshot()
	_host_root.command_link.send_graph_snapshot()

	# Both peers open Red's turn AFTER the send, not before — same reasoning
	# as `mp_procgen_sandbox.gd::_greet_if_linked_and_ready`'s docstring:
	# `TurnManager.start_turn` unconditionally fires turn-start upkeep
	# (wound-heal / node-refill included), and starting it on the HOST before
	# sending would bake an already-healed world into the snapshot, which the
	# CLIENT's own (also load-bearing — it's what sets `current_entity` so a
	# later mirrored `EndTurnCommand` isn't a silent no-op) `start_turn` call
	# would then heal a second time.
	_host_root.turn_manager.start_turn(red)
	var host_fingerprint := WorldFingerprint.compute(_host_root.graph)

	GameRoot.apply_roster({0: client_red, 1: client_blue}, GameSession.roster)
	_client_root.turn_manager.start_turn(client_red)

	return {
		"host_red": red, "host_blue": blue, "host_fingerprint": host_fingerprint,
		"client_red": client_red, "client_blue": client_blue,
	}


func test_ownership_topology_and_hp_match_after_the_join_handshake() -> void:
	var w := await _join()
	assert_eq(WorldFingerprint.compute(_client_root.graph), w["host_fingerprint"],
			"ownership + topology + HP must match once the join handshake completes")

	var client_red: Entity = w["client_red"]
	var client_blue: Entity = w["client_blue"]
	# #560: core_location rides EntitySnapshot, not GraphSnapshot — resolved
	# entity->node in its pass 2, once a graph exists to resolve against.
	assert_not_null(client_red.core_location, "core_location resolved via EntitySnapshot (#560)")
	assert_eq(client_red.core_location.owned_by, client_red)
	assert_not_null(client_blue.core_location, "core_location resolved via EntitySnapshot (#560)")
	assert_eq(client_blue.core_location.owned_by, client_blue)


func test_each_instance_is_bound_to_a_different_participant() -> void:
	var w := await _join()
	var host_red: Entity = w["host_red"]
	var client_blue: Entity = w["client_blue"]
	var host_seat := SeatPolicy.seat(host_red.entity_id)
	var client_seat := SeatPolicy.seat(client_blue.entity_id)
	assert_ne(host_seat.seated_entity_id, client_seat.seated_entity_id,
			"host is pinned to Red, client to Blue — a WANTED difference " \
			+ "(owner framing, 2026-08-22), not a divergence to chase")


## `EndTurnCommand` (→ [method TurnManager.end_turn] → `_tick_until_ready`)
## is deliberately NOT exercised here. Both of those read `Entity.GROUP` /
## `Entity.READY_GROUP` TREE-WIDE (`get_tree().get_nodes_in_group(...)`), so
## with two full worlds sharing one SceneTree they see BOTH worlds' entities
## regardless of which TurnManager is ticking — a fresh instance of exactly
## the hazard this file's own class docstring (and `test_command_link.gd`'s)
## already name for `Entity._find_turn_manager`, on a different pair of
## groups. That combination is precisely what the real two-OS-process harness
## exists to avoid; a real end-to-end multi-turn run is exercised manually
## via the Multiplayer tab (see docs/domain/multiplayer-harness.md), not in a
## single-process GUT test. What IS provable here, safely: fingerprint parity
## holds across a SEQUENCE of mirrored commands, not just the initial
## snapshot — the "keeps them identical" half of the acceptance spec that
## doesn't require crossing a turn boundary.
func test_fingerprints_stay_equal_across_a_scripted_sequence_of_commands() -> void:
	var w := await _join()
	var host_red: Entity = w["host_red"]
	var host_graph := _host_root.graph

	for round_i in 3:
		var target := _first_frontier_node(host_graph, host_red)
		if target == null:
			break
		_host_root.command_applier.submit(
				AllocateCommand.new(host_red.entity_id, host_graph.get_stable_id(target)))
		await get_tree().process_frame

		assert_eq(WorldFingerprint.compute(_client_root.graph),
				WorldFingerprint.compute(host_graph),
				"round %d: worlds must still agree" % round_i)


func _first_frontier_node(graph: Graph, red: Entity) -> SkillNode:
	for node in graph.get_skill_nodes():
		if node.owned_by != null:
			continue
		for neighbour in graph.get_neighbours(node):
			if neighbour.owned_by == red:
				return node
	return null
