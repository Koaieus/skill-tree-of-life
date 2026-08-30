extends GutTest

## #667 — [member CommandLink.defer_until_resync], the joining client's
## pre-world drop latch.
##
## [b]The window.[/b] A client opens its socket in `GameRoot._ready` BEFORE
## `_setup_level` (#463: it has nothing to build until the host's `run_setup`
## lands) and only asks for the host's world at the tail of the same method.
## Between those two points the link is up and the world is not, and a
## [constant CommandLink.KIND_COMMAND] arriving there applies against a
## half-built graph — where, worst case, a kill reaches [VictorySystem] and
## latches an outcome that has no reset.
##
## [b]Drop, not buffer.[/b] The transport is one `@rpc` on one channel and kind
## is a dictionary field, so the host encodes its resync at the moment the
## request arrives: everything applied before is already inside the envelope,
## everything after is sent after it. The assertions below are the two halves of
## that claim — nothing lands during the window, and nothing is missing once the
## resync does.
##
## The fixture is two worlds in one process, lifted from
## `test/unit/network/test_resync_backstop.gd`; the TurnManager-group caveat it
## documents applies here unchanged.

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
	link.transport = transport
	link.command_applier = world["applier"]
	link.graph = world["graph"]
	link.mode = mode
	add_child_autofree(link)
	return link


## One self-contained world: four nodes in a path, a player holding A.
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
	# Each world's entity must bind to ITS OWN TurnManager — the lookup is
	# tree-wide. See test_command_link.gd's class docstring.
	var hidden: Array[Node] = []
	for other in get_tree().get_nodes_in_group(TurnManager.GROUP):
		if other != tm:
			hidden.append(other)
			other.remove_from_group(TurnManager.GROUP)
	graph.entities_container.add_child(player)
	for other in hidden:
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


func _fp(world: Dictionary) -> int:
	return WorldFingerprint.compute(world["graph"])


## The host allocates [param id], which broadcasts a [constant
## CommandLink.KIND_COMMAND] down the wire.
func _host_allocates(id: String) -> void:
	var command := AllocateCommand.new((_host["player"] as Entity).entity_id,
			(_host["graph"] as Graph).get_stable_id(_host["nodes"][id]))
	(_host["applier"] as CommandApplier).submit(command)
	await get_tree().process_frame


func _client_owner(id: String) -> Entity:
	return (_client["nodes"][id] as SkillNode).owned_by


# --- 1. The window swallows commands ----------------------------------------

func test_a_command_during_the_window_is_not_applied() -> void:
	_client_link.defer_until_resync = true

	await _host_allocates("B")

	assert_null(_client_owner("B"),
			"the client had no world to apply this to and must not have tried")
	assert_ne(_fp(_client), _fp(_host), "so the two worlds are, for now, apart")


# --- 2. And the resync makes it whole ---------------------------------------

## The lossless half. Everything the host applied during the window is inside
## the envelope it encodes when the request arrives, so the client ends up on
## the host's world without a single command being replayed.
func test_after_the_resync_the_client_matches_the_host() -> void:
	_client_link.defer_until_resync = true
	await _host_allocates("B")
	await _host_allocates("C")

	_client_link.request_resync("join: adopting the host's world")
	await get_tree().process_frame

	assert_eq(_fp(_client), _fp(_host), "the resync carried both dropped commands")
	assert_eq(_client_owner("B"), _client["player"] as Entity)
	assert_eq(_client_owner("C"), _client["player"] as Entity)


func test_the_resync_closes_the_window() -> void:
	_client_link.defer_until_resync = true
	_client_link.request_resync("join: adopting the host's world")
	await get_tree().process_frame

	assert_false(_client_link.defer_until_resync,
			"the repair landed, so the drop window is over")

	await _host_allocates("B")

	assert_eq(_client_owner("B"), _client["player"] as Entity,
			"and ordinary commands apply again from here on")


# --- 3. The join's own payloads must NOT be gated ---------------------------

## Gating these deadlocks the join: they are how the client gets a world at all.
func test_a_graph_snapshot_still_lands_inside_the_window() -> void:
	_client_link.defer_until_resync = true
	(_client["nodes"]["B"] as SkillNode).allocation_level = 3
	assert_ne(_fp(_client), _fp(_host), "the fixture must actually be diverged")

	_host_link.send_graph_snapshot()
	await get_tree().process_frame

	assert_eq(_fp(_client), _fp(_host),
			"KIND_SNAPSHOT is not a world mutation, it IS the world")


# --- 4. Off by default ------------------------------------------------------

## Every host, offline sandbox and existing mp harness runs with the flag down.
func test_the_latch_is_off_by_default() -> void:
	assert_false(_client_link.defer_until_resync)

	await _host_allocates("B")

	assert_eq(_client_owner("B"), _client["player"] as Entity)
	assert_eq(_fp(_client), _fp(_host))


# --- 5. The two non-command kinds, decided explicitly ------------------------

## [constant CommandLink.KIND_LOOT_OFFER] is not a [Command], but it parks state
## on the receiver: it resolves `collector_id` through the applier's graph (null
## mid-generation), binds a `died` handler on an entity the resync is about to
## reconcile, and holds `LootSystem._pending_mirror_request`. It also cannot be
## FOR a peer that is still joining, and the whole window is pre-HUD, so nothing
## would be listening to answer it anyway. Dropped — see
## [constant CommandLink.DEFERRED_KINDS] for the full ruling, including why
## KIND_INTENT needs no guard here (host-only handler; this latch only ever
## rides a MIRROR peer).
func test_a_loot_offer_during_the_window_is_dropped() -> void:
	var offers: Array = []
	_client_link.loot_offer_received.connect(func(o: LootPickOffer) -> void: offers.append(o))
	var offer := LootPickOffer.new()
	offer.request_id = 7
	offer.collector_id = (_host["player"] as Entity).entity_id

	_client_link.defer_until_resync = true
	_host_link.send_loot_offer(offer)
	await get_tree().process_frame
	assert_true(offers.is_empty(), "no picker may open against a world that does not exist")

	_client_link.defer_until_resync = false
	_host_link.send_loot_offer(offer)
	await get_tree().process_frame
	assert_eq(offers.size(), 1, "and it is the window that gates it, not the kind")
