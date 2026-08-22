extends GutTest

## #532 acceptance bullet 5a: a host-side [EndTurnCommand] really advances the
## CLIENT's own [TurnManager], not only the host's — the "it only ended
## locally" failure the harness exists to make loud.
##
## Fixture shape mirrors test_command_link.gd's two-world pattern, extended
## with a SECOND entity per world so the turn hands off to somebody rather
## than just going idle — a fixture that could pass by "current_entity became
## null on both" would not distinguish a real handover from a no-op.

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


## Two entities: P1 (opens the turn) and P2 (where it hands off to).
func _build_world(label: String) -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	graph.name = "Graph_%s" % label
	add_child_autofree(graph)

	var a := _SKILL_NODE_SCENE.instantiate() as SkillNode
	a.name = "A"
	graph.add_skill_node(a)
	var b := _SKILL_NODE_SCENE.instantiate() as SkillNode
	b.name = "B"
	graph.add_skill_node(b)

	var tm: TurnManager = autofree(TurnManager.new())
	tm.name = "TurnManager_%s" % label
	add_child(tm)

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	alloc.navigator = graph.navigator
	alloc.turn_manager = tm
	add_child_autofree(alloc)

	var p1: Entity = autofree(Entity.new())
	p1.display_name = "P1_%s" % label
	p1.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(p1)

	var p2: Entity = autofree(Entity.new())
	p2.display_name = "P2_%s" % label
	p2.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(p2)

	await get_tree().process_frame

	p1.core_location = a
	alloc.force_allocate(p1, a)
	p2.core_location = b
	alloc.force_allocate(p2, b)
	tm.start_turn(p1)

	var applier := CommandApplier.new()
	applier.graph = graph
	applier.allocation_system = alloc
	applier.turn_manager = tm
	add_child_autofree(applier)

	return {"graph": graph, "tm": tm, "applier": applier, "p1": p1, "p2": p2}


func test_host_end_turn_advances_the_clients_turn_manager() -> void:
	var host_tm: TurnManager = _host["tm"]
	var client_tm: TurnManager = _client["tm"]
	var host_p1: Entity = _host["p1"]
	var client_p1: Entity = _client["p1"]

	assert_eq(host_tm.current_entity, host_p1, "sanity: host P1 opens")
	assert_eq(client_tm.current_entity, client_p1, "sanity: client mirrors the same opening state")

	(_host["applier"] as CommandApplier).submit(EndTurnCommand.new(host_p1.entity_id))
	await get_tree().process_frame

	assert_ne(host_tm.current_entity, host_p1, "sanity: the host's own turn advanced")
	assert_ne(client_tm.current_entity, client_p1,
			"a host-side end_turn must advance the CLIENT's own TurnManager too — " \
			+ "not only the host's")
