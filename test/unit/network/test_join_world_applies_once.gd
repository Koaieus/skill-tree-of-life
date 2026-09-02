extends GutTest

## #715 — the join race has two legs and exactly one of them may land.
##
## The host PUSHES its world when a peer joins (`GameRoot._on_peer_joined`) AND
## answers the client's PULL (`GameRoot.pull_host_world` ->
## `CommandLink._on_resync_request`), because either leg alone can be dropped in
## silence — see the comment block at `_on_peer_joined`. So on the happy path the
## client receives TWO whole worlds, and applying the second would re-decode a
## world it already holds, re-emit [signal CommandLink.resync_applied] (whose
## `GameRoot` handler re-derives seat vision and controllers) and re-enter
## `entity_spawner` for every materialised blocker.
##
## The guard is a flag on the message, not a fingerprint compare: the fold does
## not cover tags or effects, so a mid-run repair whose fingerprints already
## agree must STILL apply. These tests pin both halves of that.
##
## The fixture is deliberately small — one link pair, one graph each — because
## what is under test is `_on_resync`'s guard, not the decode. The populated
## repair path itself is `test_resync_backstop.gd`'s job.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _host_graph: Graph
var _client_graph: Graph
var _host_link: CommandLink
var _client_link: CommandLink
var _applied: Array[String]


func before_each() -> void:
	_host_graph = _build_graph("host", 4)
	_client_graph = _build_graph("client", 0)
	var pair := LoopbackTransport.pair()
	add_child_autofree(pair[0])
	add_child_autofree(pair[1])
	_host_link = _make_link(_host_graph, pair[0], CommandLink.Mode.BROADCAST)
	_client_link = _make_link(_client_graph, pair[1], CommandLink.Mode.MIRROR)
	_applied = []
	_client_link.resync_applied.connect(func(r: String) -> void: _applied.append(r))


func _make_link(graph: Graph, transport: NetworkTransport, mode: CommandLink.Mode) -> CommandLink:
	var link := CommandLink.new()
	link.transport = transport
	link.graph = graph
	link.mode = mode
	add_child_autofree(link)
	return link


## A path of [param count] nodes. `count == 0` is the joining client's world:
## empty, which since #715 is the primary shape rather than the odd one.
func _build_graph(label: String, count: int) -> Graph:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	graph.name = "Graph_%s" % label
	add_child_autofree(graph)
	var previous: SkillNode = null
	for i in count:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		graph.add_skill_node(sn)
		if previous != null:
			graph.add_edge(previous, sn)
		previous = sn
	return graph


func _push_join_world() -> void:
	_host_link.send_resync("join: the peer is on the link and has no world", true)
	await get_tree().process_frame


func _pull_join_world() -> void:
	# Exactly what `GameRoot.pull_host_world` sends.
	_client_link.request_resync("join: adopting the host's world", true)
	await get_tree().process_frame


# --- 1. Both legs land; the world is applied once ----------------------------

func test_the_hosts_push_and_the_clients_pull_apply_the_world_exactly_once() -> void:
	# The real order on the wire: the host pushes on `peer_joined`, the client's
	# request arrives after, and the host answers it. Two whole worlds arrive.
	await _push_join_world()
	assert_eq(_client_graph.get_skill_nodes().size(), 4,
			"the first leg is what gives the joining peer a world at all")
	assert_eq(_applied.size(), 1, "and it counts as the world arriving")

	await _pull_join_world()

	assert_eq(_applied.size(), 1,
			"the second leg carries the SAME world and must not be applied again: %s" % [_applied])
	assert_eq(_client_graph.get_skill_nodes().size(), 4,
			"and the world it already held is untouched")
	assert_eq(WorldFingerprint.compute(_client_graph), WorldFingerprint.compute(_host_graph),
			"dropping the loser does not cost convergence")


## The race the other way round — the client's pull is answered first and the
## host's push loses. Neither leg is privileged; whichever is first wins.
func test_whichever_leg_arrives_first_is_the_one_that_applies() -> void:
	await _pull_join_world()
	assert_eq(_applied.size(), 1, "the answer to the pull gave this peer its world")

	await _push_join_world()

	assert_eq(_applied.size(), 1, "so the host's push is the redundant one this time: %s" % [_applied])
	assert_eq(WorldFingerprint.compute(_client_graph), WorldFingerprint.compute(_host_graph),
			"and the worlds still agree")


## The drop is not "a world is present" — it is "the JOIN's world already
## arrived". Belt and braces on the guard's scope.
func test_the_join_flag_rides_the_request_through_to_the_answer() -> void:
	var seen: Array[Dictionary] = []
	(_client_link.transport as NetworkTransport).message_received.connect(
			func(p: Dictionary) -> void: seen.append(p))

	await _pull_join_world()

	var resyncs: Array[Dictionary] = []
	for payload in seen:
		if String(payload.get(CommandLink.KEY_KIND, "")) == CommandLink.KIND_RESYNC:
			resyncs.append(payload)
	assert_eq(resyncs.size(), 1, "the host answered the pull once")
	assert_true(bool(resyncs[0].get(CommandLink.KEY_JOIN, false)),
			"and the answer is flagged as the join's world, not as a repair — "
			+ "the flag was set on the REQUEST and `_on_resync_request` forwards it")


# --- 2. A mid-run repair is untouched ----------------------------------------

## The path the guard must NOT break (#521/#560/#561). An unflagged repair is
## an ordinary mid-run repair however many join worlds preceded it — which is
## also why the guard keys off the message flag rather than off a fingerprint
## compare, since `WorldFingerprint`'s fold does not cover tags or effects
## (`test_resync_backstop.gd::test_a_stacked_tag_survives_the_repair_at_its_full_count`
## is the repair that a fingerprint compare would have silently swallowed).
func test_a_mid_run_repair_still_applies_after_the_join_world_has_arrived() -> void:
	await _push_join_world()
	assert_eq(_applied.size(), 1, "the join's world landed")

	var host_node: SkillNode = _host_graph.get_skill_nodes()[1]
	var stable_id := _host_graph.get_stable_id(host_node)
	host_node.allocation_level = 3
	assert_ne(WorldFingerprint.compute(_client_graph), WorldFingerprint.compute(_host_graph),
			"the fixture must actually be diverged")

	_host_link.send_resync("verdict: the peer drifted")
	await get_tree().process_frame

	assert_eq(_applied.size(), 2, "an unflagged repair is never dropped: %s" % [_applied])
	var repaired := _client_graph.get_by_stable_id(stable_id)
	assert_not_null(repaired, "and it reached the node it was about to repair")
	assert_eq(WorldFingerprint.compute(_client_graph), WorldFingerprint.compute(_host_graph),
			"so the repair path this guard must not break still converges")
