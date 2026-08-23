extends GutTest

## The multiplayer harness's mirror seam: a command confirmed on the host is
## broadcast, applied by the client's own [CommandApplier], and the two worlds
## agree afterwards.
##
## [b]Two worlds in one process is fine HERE and nowhere else.[/b] The harness
## itself launches two OS processes because [Events] is a process-global bus
## carrying live node/entity references — but nothing in this file kills
## anything, so none of the death/loot/victory listeners that cross-wire ever
## fire. Add a test that kills an entity and it belongs in a separate file with
## one world, not here.
##
## [b]The death listeners are not the only tree-wide lookup.[/b]
## [method Entity._find_turn_manager] (and [EntityController]) resolve their
## manager with `get_first_node_in_group(TurnManager.GROUP)` — TREE-wide, not
## world-scoped. Correct by construction in a real one-world process; here the
## SECOND world's entity would silently bind to the FIRST world's TurnManager,
## never receive its own `turn_started`, and so never run
## `apply_per_turn_upkeep()` — diverging in every pool that upkeep feeds
## (xp → level → constitution → node_health). `_build_world` scopes the group
## while each entity binds, and `test_both_worlds_run_their_own_turn_upkeep`
## guards it. This was invisible while [WorldFingerprint] folded ownership
## only; it surfaced the moment #527 folded HP.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _host: Dictionary
var _client: Dictionary
var _host_link: CommandLink
var _client_link: CommandLink


func before_each() -> void:
	_host = await _build_world("host")
	_client = await _build_world("client")

	var pair := LoopbackTransport.pair()
	add_child_autofree(pair[0])
	add_child_autofree(pair[1])

	_host_link = _make_link(_host, pair[0], CommandLink.Mode.BROADCAST)
	_client_link = _make_link(_client, pair[1], CommandLink.Mode.MIRROR)


func _make_link(world: Dictionary, transport: NetworkTransport, mode: CommandLink.Mode) -> CommandLink:
	var link := CommandLink.new()
	# Exports before `add_child`: `_ready` is what connects the signals.
	link.transport = transport
	link.command_applier = world["applier"]
	link.graph = world["graph"]
	link.mode = mode
	add_child_autofree(link)
	return link


## One self-contained world: graph, four nodes in a path, a player holding A.
## Shaped after `test/unit/command/test_command_applier.gd`'s fixture — the
## entity must enter `entities_container` for its `entity_id` to mint (#509).
func _build_world(label: String) -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	graph.name = "Graph_%s" % label
	add_child_autofree(graph)

	var nodes: Dictionary = {}
	for id in ["A", "B", "C", "D"]:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = id
		graph.add_skill_node(sn)
		nodes[id] = sn
	graph.add_edge(nodes["A"], nodes["B"])
	graph.add_edge(nodes["B"], nodes["C"])
	graph.add_edge(nodes["C"], nodes["D"])

	var tm: TurnManager = autofree(TurnManager.new())
	tm.name = "TurnManager_%s" % label
	add_child(tm)

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	alloc.navigator = graph.navigator
	alloc.turn_manager = tm
	add_child_autofree(alloc)

	var player: Entity = autofree(Entity.new())
	player.display_name = "Player_%s" % label
	player.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# See the class docstring: the entity binds its TurnManager by a TREE-wide
	# group lookup, so hide every OTHER world's manager for the duration of the
	# bind. Restored immediately after — `start_turn` is called on the `tm`
	# reference directly, so group membership only matters during binding.
	var hidden_managers: Array[Node] = []
	for other in get_tree().get_nodes_in_group(TurnManager.GROUP):
		if other != tm:
			hidden_managers.append(other)
			other.remove_from_group(TurnManager.GROUP)
	graph.entities_container.add_child(player)
	for other in hidden_managers:
		other.add_to_group(TurnManager.GROUP)

	await get_tree().process_frame

	player.core_location = nodes["A"]
	alloc.force_allocate(player, nodes["A"])
	tm.start_turn(player)
	player.stat_board.skill_points.grant(5)

	var applier := CommandApplier.new()
	applier.graph = graph
	applier.allocation_system = alloc
	applier.turn_manager = tm
	add_child_autofree(applier)

	return {
		"graph": graph, "alloc": alloc, "tm": tm,
		"applier": applier, "player": player, "nodes": nodes,
	}


func _id(world: Dictionary, key: String) -> int:
	return (world["graph"] as Graph).get_stable_id(world["nodes"][key])


## Guards the fixture invariant the class docstring describes: each world's
## entity must bind to ITS OWN TurnManager. When it doesn't, the symptom is not
## an error — it is one entity silently skipping `apply_per_turn_upkeep()`, so
## the two worlds drift apart in xp → level → constitution → node_health while
## every ownership assertion in this file still passes. Asserting on
## `node_health` rather than on the binding directly is deliberate: it is the
## observable a fingerprint folding accumulated state would trip over.
func test_both_worlds_run_their_own_turn_upkeep() -> void:
	var host_hp: float = (_host["player"] as Entity).stat_board \
			.get_stat(&"node_health").get_value()
	var client_hp: float = (_client["player"] as Entity).stat_board \
			.get_stat(&"node_health").get_value()
	assert_eq(host_hp, client_hp,
			"both worlds' players must receive their own turn upkeep")


func test_two_identical_worlds_fingerprint_the_same() -> void:
	assert_eq(WorldFingerprint.compute(_host["graph"]), WorldFingerprint.compute(_client["graph"]),
			"same authored topology + same ownership must hash equal, or every " \
			+ "sync check downstream is noise")


func test_a_confirmed_allocate_mirrors_to_the_client() -> void:
	var command := AllocateCommand.new((_host["player"] as Entity).entity_id, _id(_host, "B"))
	(_host["applier"] as CommandApplier).submit(command)
	await get_tree().process_frame

	assert_eq((_client["nodes"]["B"] as SkillNode).owned_by, _client["player"] as Entity,
			"the client's own applier should have run the mirrored allocate")
	assert_eq(WorldFingerprint.compute(_client["graph"]), WorldFingerprint.compute(_host["graph"]),
			"worlds must agree after a mirrored command")


func test_a_refused_command_is_not_broadcast() -> void:
	# D is not adjacent to the player's only owned node, so the gate refuses it.
	var command := AllocateCommand.new((_host["player"] as Entity).entity_id, _id(_host, "D"))
	(_host["applier"] as CommandApplier).submit(command)
	await get_tree().process_frame

	assert_null((_client["nodes"]["D"] as SkillNode).owned_by,
			"a command the host's gate refused changed nothing, so there is " \
			+ "nothing to mirror")


# ── The fingerprint compares pre-state against pre-state (#540 decision 4) ──

func test_the_broadcast_fingerprint_is_the_pre_command_world() -> void:
	# Once the host confirms BEFORE it applies, there is no post-mutation world
	# to sample at confirm time. So the payload carries the world the host was
	# about to mutate, stamped by the applier when the command left its queue.
	var before := WorldFingerprint.compute(_host["graph"])
	var payloads: Array[Dictionary] = []
	(_client_link.transport as NetworkTransport).message_received.connect(
			func(p: Dictionary) -> void: payloads.append(p))

	var command := AllocateCommand.new((_host["player"] as Entity).entity_id, _id(_host, "B"))
	(_host["applier"] as CommandApplier).submit(command)
	await get_tree().process_frame

	assert_eq(payloads.size(), 1, "exactly one command crossed")
	assert_eq(int(payloads[0][CommandLink.KEY_FINGERPRINT]), before,
			"the host ships the world it was ABOUT to mutate, not the one it just made")
	assert_ne(WorldFingerprint.compute(_host["graph"]), before,
			"and the command really did move the host's world, so the two differ")


func test_the_client_compares_before_it_applies() -> void:
	# The other half of the same claim. Comparing post-apply against a pre-apply
	# fingerprint would read as divergence on every single command and take
	# #529's WORLD column with it.
	var verdicts: Array[bool] = []
	var owner_at_check: Array = [&"unset"]
	_client_link.sync_checked.connect(func(agrees: bool, _l: int, _r: int) -> void:
		verdicts.append(agrees)
		owner_at_check[0] = (_client["nodes"]["B"] as SkillNode).owned_by)

	var command := AllocateCommand.new((_host["player"] as Entity).entity_id, _id(_host, "B"))
	(_host["applier"] as CommandApplier).submit(command)
	await get_tree().process_frame

	assert_eq(verdicts, [true] as Array[bool],
			"pre-state against pre-state agrees — a false here means decision 4 is wrong, " \
			+ "not that the worlds diverged")
	assert_null(owner_at_check[0],
			"and the comparison ran before the client's own applier had touched B")


func test_the_wire_carries_no_pre_fingerprint_field_in_the_command() -> void:
	# `pre_fingerprint` is transient applier state riding the ENVELOPE. Putting
	# it in the command dict would invalidate every committed outcome fixture
	# (#539) — those .tres files ARE serialized command dictionaries.
	var payloads: Array[Dictionary] = []
	(_client_link.transport as NetworkTransport).message_received.connect(
			func(p: Dictionary) -> void: payloads.append(p))

	(_host["applier"] as CommandApplier).submit(
			AllocateCommand.new((_host["player"] as Entity).entity_id, _id(_host, "B")))
	await get_tree().process_frame

	assert_false((payloads[0][CommandLink.KEY_COMMAND] as Dictionary).has("pre_fingerprint"),
			"the command's own namespace stays the codec's")


func test_the_client_does_not_echo_back() -> void:
	var host_applier: CommandApplier = _host["applier"]
	var seen: Array[String] = []
	host_applier.command_applied.connect(
			func(c: Command, _ok: bool) -> void: seen.append(String(c.type_tag())))

	var command := AllocateCommand.new((_host["player"] as Entity).entity_id, _id(_host, "B"))
	host_applier.submit(command)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(seen.size(), 1, "the host must apply its command exactly once — a " \
			+ "client that echoed would re-enter the host forever")


func test_divergence_is_visible_as_a_fingerprint_mismatch() -> void:
	# Mutate ONLY the client, the way an unmirrored attack or loot roll would.
	(_client["alloc"] as AllocationSystem).force_allocate(
			_client["player"] as Entity, _client["nodes"]["B"] as SkillNode)

	assert_ne(WorldFingerprint.compute(_client["graph"]), WorldFingerprint.compute(_host["graph"]),
			"a world change that never crossed the wire must show up as a " \
			+ "mismatch — that is the harness's whole diagnostic value")


func test_loopback_never_delivers_to_the_sender() -> void:
	var pair := LoopbackTransport.pair()
	var host_got: Array[Dictionary] = []
	var client_got: Array[Dictionary] = []
	pair[0].message_received.connect(func(p: Dictionary) -> void: host_got.append(p))
	pair[1].message_received.connect(func(p: Dictionary) -> void: client_got.append(p))

	pair[0].send({"kind": "ping"})

	assert_eq(client_got.size(), 1, "the other end receives")
	assert_eq(host_got.size(), 0, "a self-echo would re-apply what the sender " \
			+ "already applied")
	pair[0].free()
	pair[1].free()
