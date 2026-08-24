extends GutTest

## #561 — the host-authoritative resync backstop. A desync verdict does not just
## get logged and left: the authority pushes the whole world back, so play
## continues, AND the verdict still shouts (#521 D3, both halves).
##
## [b]The fixture is two worlds in one process[/b], the same arrangement — and
## the same TurnManager-group caveat — `test/unit/network/test_command_link.gd`
## documents at length. Nothing here kills anything, so none of the process-global
## death/loot listeners cross-wire.
##
## [b]What the assertions are really about.[/b] A resync is a REPAIR: it decodes
## into a graph that is already populated and already correct in most of its
## parts, so the tests below check not only that the world ends up right but that
## nothing was animated getting there (acceptance 6) and that a world which never
## drifted is never repaired at all (acceptance 3).

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


## Everything the client end put ON the wire, i.e. everything the host received.
func _sniff_upward() -> Array[Dictionary]:
	var seen: Array[Dictionary] = []
	(_host_link.transport as NetworkTransport).message_received.connect(
			func(p: Dictionary) -> void: seen.append(p))
	return seen


func _kinds(payloads: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for p in payloads:
		out.append(String(p.get(CommandLink.KEY_KIND, "")))
	return out


## Move the client's world off the host's without touching the host's — the
## "the client's number crept wrong" bug class this whole feature exists for.
func _drift_the_client() -> void:
	(_client["nodes"]["B"] as SkillNode).allocation_level = 3


# --- 1. A verdict triggers a resync -----------------------------------------

func test_a_verdict_triggers_a_resync() -> void:
	_drift_the_client()
	assert_ne(_fp(_client), _fp(_host), "the fixture must actually be diverged")

	_host_link.send_hello()
	await get_tree().process_frame

	assert_eq(_fp(_client), _fp(_host),
			"the verdict must have pulled the client's world back onto the host's")


# --- 2. And it still shouts (#521 D3) ---------------------------------------

func test_a_verdict_shouts_as_loudly_as_before_the_auto_heal() -> void:
	var lines: Array[String] = []
	_client_link.logged.connect(func(l: String) -> void: lines.append(l))
	var verdicts: Array = []
	_client_link.sync_checked.connect(
			func(a: bool, l: int, r: int) -> void: verdicts.append([a, l, r]))

	_drift_the_client()
	var wrong := _fp(_client)
	var right := _fp(_host)
	_host_link.send_hello()
	await get_tree().process_frame

	assert_eq(verdicts.size(), 1, "exactly one comparison happened")
	assert_false(verdicts[0][0], "and it must still report FALSE — the heal does not swallow it")
	assert_eq(verdicts[0][1], wrong, "the verdict names the local fingerprint")
	assert_eq(verdicts[0][2], right, "and the remote one")

	var shouted := false
	for line in lines:
		if line.contains("DIVERGED") and line.contains(str(wrong)) and line.contains(str(right)):
			shouted = true
	assert_true(shouted, "the divergence must be logged with both fingerprints named: %s" % [lines])


# --- 3. A green run never resyncs -------------------------------------------

func test_a_green_run_never_resyncs() -> void:
	var pushes: Array[String] = []
	_host_link.resync_sent.connect(func(r: String) -> void: pushes.append(r))
	var upward := _sniff_upward()

	_host_link.send_hello()
	await get_tree().process_frame
	var command := AllocateCommand.new((_host["player"] as Entity).entity_id,
			(_host["graph"] as Graph).get_stable_id(_host["nodes"]["B"]))
	(_host["applier"] as CommandApplier).submit(command)
	await get_tree().process_frame

	assert_eq(_fp(_client), _fp(_host), "the fixture ran green")
	assert_true(pushes.is_empty(), "a world that never drifted is never repaired: %s" % [pushes])
	assert_false(_kinds(upward).has(CommandLink.KIND_RESYNC_REQUEST),
			"and the client never asked")


# --- 4. Only the host sends state (#521 D4) ---------------------------------

func test_a_client_asks_and_never_reconstructs() -> void:
	var upward := _sniff_upward()
	_drift_the_client()
	_host_link.send_hello()
	await get_tree().process_frame

	var kinds := _kinds(upward)
	for state_kind in [CommandLink.KIND_RESYNC, CommandLink.KIND_SNAPSHOT, CommandLink.KIND_ENTITIES]:
		assert_false(kinds.has(state_kind),
				"a client must never put %s on the wire — only the authority sends state" % state_kind)
	assert_eq(kinds.count(CommandLink.KIND_RESYNC_REQUEST), 1,
			"it asks exactly once, and the latch stops it asking again: %s" % [kinds])


# --- 5. Into a POPULATED graph (D6) -----------------------------------------

func test_a_resync_repairs_a_populated_graph_exactly() -> void:
	var client_graph: Graph = _client["graph"]
	# Three kinds of drift at once: a node the host does not have, an edge the
	# host does not have, and an edge the host DOES have that this peer lost.
	var stray := _SKILL_NODE_SCENE.instantiate() as SkillNode
	stray.name = "E"
	client_graph.add_skill_node(stray)
	client_graph.add_edge(_client["nodes"]["D"], stray)
	for edge in client_graph.get_edges():
		if edge.from == _client["nodes"]["A"] and edge.to == _client["nodes"]["B"]:
			client_graph.remove_edge(edge)
	await get_tree().process_frame

	_host_link.send_resync("test")
	await get_tree().process_frame

	var host_graph: Graph = _host["graph"]
	assert_eq(client_graph.get_skill_nodes().size(), host_graph.get_skill_nodes().size(),
			"no orphan node survives, and none is duplicated")
	assert_eq(_stable_ids(client_graph), _stable_ids(host_graph),
			"the same stable ids, with no collisions")
	assert_eq(client_graph.get_edges().size(), host_graph.get_edges().size(),
			"the lost edge is back and the invented one is gone")
	assert_eq(_fp(_client), _fp(_host), "so the two worlds fingerprint the same")


func _stable_ids(graph: Graph) -> Array:
	var ids: Array = []
	for node in graph.get_skill_nodes():
		ids.append(graph.get_stable_id(node))
	ids.sort()
	return ids


## The reconcile's other half of D6: a node that did NOT drift is the SAME
## object afterwards. That is what preserves every live reference a repair has
## no business disturbing — an entity's `core_location`, an [EffectInstance]'s
## `source_node`, a navigator mirror.
func test_a_node_that_never_drifted_is_not_rebuilt() -> void:
	var before: SkillNode = _client["nodes"]["C"]
	_drift_the_client()
	_host_link.send_hello()
	await get_tree().process_frame

	var after := (_client["graph"] as Graph).get_by_stable_id(
			(_host["graph"] as Graph).get_stable_id(_host["nodes"]["C"]))
	assert_eq(after, before, "a repair reconciles in place; it does not tear the world down")
	assert_eq((_client["player"] as Entity).core_location, _client["nodes"]["A"],
			"and the entity's core node is still the object it was")


# --- 6. A resync is not an event --------------------------------------------

func test_a_resync_does_not_animate() -> void:
	var confirmed: Array = []
	var applied: Array = []
	(_client["applier"] as CommandApplier).command_confirmed.connect(
			func(c: Command) -> void: confirmed.append(c))
	(_client["applier"] as CommandApplier).command_applied.connect(
			func(c: Command, _ok: bool) -> void: applied.append(c))

	_drift_the_client()
	_host_link.send_hello()
	await get_tree().process_frame

	assert_true(confirmed.is_empty(),
			"nothing confirms — #525's camera director pans on that signal and must not pan for a repair")
	assert_true(applied.is_empty(), "and no command was applied: a repair is not an event")
	assert_false((_client["applier"] as CommandApplier).is_applying,
			"nor did it leave the applier mid-beat")


# --- Gap 1: an entity the authority does not have -----------------------------

func test_a_resync_removes_an_entity_the_authority_does_not_have() -> void:
	var stray := Entity.new()
	stray.display_name = "Stray"
	stray.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	(_client["graph"] as Graph).entities_container.add_child(stray)
	await get_tree().process_frame
	var stray_id := stray.entity_id
	assert_ne(stray_id, 0, "the fixture's stray entity must have minted an id")

	_host_link.send_resync("test")
	await get_tree().process_frame

	assert_null((_client["graph"] as Graph).get_by_entity_id(stray_id),
			"an entity the payload does not name does not exist in the authority's world")
	assert_eq(EntitySnapshot.entities_of(_client["graph"]).size(),
			EntitySnapshot.entities_of(_host["graph"]).size(),
			"no duplicates, no orphans")


# --- Gap 2: tag refcounts cross the wire --------------------------------------

func test_a_stacked_tag_survives_the_repair_at_its_full_count() -> void:
	var host_player: Entity = _host["player"]
	host_player.add_tag(&"burning")
	host_player.add_tag(&"burning")
	host_player.add_tag(&"chilled")
	var client_player: Entity = _client["player"]
	# The client holds it once and holds a marker the host does not.
	client_player.add_tag(&"burning")
	client_player.add_tag(&"blessed")

	_host_link.send_resync("test")
	await get_tree().process_frame

	assert_eq(client_player.get_tag_count(&"burning"), 2,
			"a tag applied twice and removed once is still active — the COUNT has to cross")
	assert_eq(client_player.get_tag_count(&"chilled"), 1, "and a missing tag is restored")
	assert_false(client_player.has_tag(&"blessed"), "a tag the authority does not hold comes off")
