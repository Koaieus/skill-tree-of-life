extends GutTest

## #532 decision 2: a MIRROR peer's own [AIController] must never submit.
##
## [method GameRoot._ensure_controllers] attaches an [AIController] to every
## non-human entity on BOTH peers of the multiplayer harness, and that
## controller resolves its OWN peer's [CommandApplier] — so without a gate, a
## client's copy of a non-human entity's AI would decide and submit
## independently of the host's AI the instant a mirrored [EndTurnCommand] hands
## it the turn locally. [member CommandApplier.is_authority] is the existing
## "am I the one who decides" flag ([SkillDustAddon]'s claim flow already gates
## on it); this pins [AIController.take_turn] extending the same invariant.
##
## Fixture mirrors test_ai_controller.gd's TurnManager + Entity + AIController
## setup, minus BattleSystem — the gate fires before any combat step runs, so
## it is not needed.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _applier: CommandApplier
var _player: Entity
var _enemy: Entity
var _ai: AIController
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_nodes = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(i * 100.0, 0.0)
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	_add_edge(_nodes[0], _nodes[1])
	_add_edge(_nodes[1], _nodes[2])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_applier = CommandApplier.new()
	_applier.graph = _graph
	_applier.allocation_system = _alloc
	_applier.turn_manager = _tm
	add_child_autofree(_applier)

	# A second (idle) entity so TurnManager has somewhere to hand the turn
	# after the AI ends its own — see test_ai_controller.gd's fixture note on
	# why this avoids a turn_delay=0 recursion.
	_player = Entity.new()
	_player.name = "Player"
	_player.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_player)
	_player.add_child(PlayerController.new())

	_enemy = Entity.new()
	_enemy.name = "Enemy"
	_enemy.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_enemy)
	_ai = AIController.new()
	_ai.turn_delay = 0.0
	_ai.command_applier_override = _applier
	_enemy.add_child(_ai)

	await get_tree().process_frame

	_alloc.force_allocate(_enemy, _nodes[0])
	_enemy.core_location = _nodes[0]
	_enemy.stat_board.skill_points.set_current(3)


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


func test_non_authority_ai_does_not_submit_on_its_turn() -> void:
	_applier.is_authority = false
	var submitted: Array[Command] = []
	_applier.command_applied.connect(func(c: Command, _ok: bool) -> void: submitted.append(c))

	_tm.start_turn(_enemy)
	await get_tree().create_timer(0.3).timeout

	assert_true(submitted.is_empty(),
			"a non-authority AIController must never submit a command on its own turn")


## Same fixture, authority restored — proves the assert above is the gate
## doing something, not a fixture that never acts at all.
func test_authority_ai_still_acts() -> void:
	_applier.is_authority = true
	var submitted: Array[Command] = []
	_applier.command_applied.connect(func(c: Command, _ok: bool) -> void: submitted.append(c))

	_tm.start_turn(_enemy)
	await get_tree().create_timer(0.3).timeout

	assert_false(submitted.is_empty(),
			"sanity: the authority's own AI still submits — this fixture is capable of it")
