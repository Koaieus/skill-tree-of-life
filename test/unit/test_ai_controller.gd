extends GutTest

## Coverage for #378 slice A: fog-aware recon short-circuit + the
## Events.ai_decision seam on [AIController].
##
## Fixture mirrors test_turn_handoff.gd's TurnManager + Entity + AIController
## setup, minus BattleSystem (not needed — no hostile is ever visible or
## reachable in these fixtures, so the attack step never engages it).

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _player: Entity
var _enemy: Entity
var _ai: AIController
var _nodes: Array[SkillNode]

var _decisions: Array[String] = []


func _make_entity(ent_name: String) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	return e


func before_each() -> void:
	_decisions = []

	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	# Core – frontier line, all unowned except the core.
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

	# A second (idle) entity so TurnManager has somewhere to hand the turn
	# after the AI ends its own — PlayerController.take_turn is a no-op, so
	# the clock parks there instead of immediately re-selecting the AI and
	# recursing take_turn synchronously (stack overflow with turn_delay=0).
	#
	# Controllers are added AFTER their entity enters the tree (matching
	# GameRoot._ensure_controllers, which runs post-_setup_level) so
	# Entity's own turn_started connection (per-turn upkeep) registers
	# before the controller's — upkeep must run before take_turn, not
	# race it inside the same synchronous emit().
	_player = _make_entity("Player")
	_graph.add_child(_player)
	_player.add_child(PlayerController.new())

	_enemy = _make_entity("Enemy")
	_graph.add_child(_enemy)
	_ai = AIController.new()
	_ai.turn_delay = 0.0
	_ai.allocation_system_override = _alloc
	_enemy.add_child(_ai)

	await get_tree().process_frame

	_alloc.force_allocate(_enemy, _nodes[0])
	_enemy.core_location = _nodes[0]

	Events.ai_decision.connect(_on_ai_decision)


func after_each() -> void:
	if Events.ai_decision.is_connected(_on_ai_decision):
		Events.ai_decision.disconnect(_on_ai_decision)


func _on_ai_decision(_entity: Entity, summary: String) -> void:
	_decisions.append(summary)


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


# ---------------------------------------------------------------------------
# Fog short-circuit
# ---------------------------------------------------------------------------

func test_fog_short_circuit_ends_turn_without_attack() -> void:
	# No hostile entity in the graph at all -> AiRecon sees nothing.
	_enemy.stat_board.skill_points.set_current(1)
	_tm.start_turn(_enemy)

	await get_tree().create_timer(0.3).timeout

	assert_true(_decisions.has("no visible hostile — growth only"),
			"growth-only decision should have been recorded")
	assert_ne(_tm.current_entity, _enemy, "turn should have ended")


func test_fog_short_circuit_still_spends_all_sp() -> void:
	# Only 2 frontier nodes exist (N1, N2) in this fixture — growth exhausts
	# the frontier regardless of exactly how much SP is on hand (turn-start
	# XP upkeep can mint extra SP via level-up; that economy isn't this
	# test's concern). What #378 requires is the loop not stopping early:
	# every reachable frontier node gets allocated before the turn ends.
	_enemy.stat_board.skill_points.set_current(2)
	_tm.start_turn(_enemy)

	await get_tree().create_timer(0.3).timeout

	assert_eq(_nodes[1].owned_by, _enemy, "frontier node 1 allocated")
	assert_eq(_nodes[2].owned_by, _enemy, "frontier node 2 allocated")


# ---------------------------------------------------------------------------
# Events.ai_decision — always emitted, debug_trace only gates the console sink
# ---------------------------------------------------------------------------

func test_ai_decision_emitted_regardless_of_debug_trace() -> void:
	_ai.debug_trace = false
	_enemy.stat_board.skill_points.set_current(0)
	_tm.start_turn(_enemy)

	await get_tree().create_timer(0.3).timeout

	assert_gt(_decisions.size(), 0, "Events.ai_decision must fire even with debug_trace off")


func test_ai_decision_emitted_with_debug_trace_on() -> void:
	_ai.debug_trace = true
	_enemy.stat_board.skill_points.set_current(0)
	_tm.start_turn(_enemy)

	await get_tree().create_timer(0.3).timeout

	assert_gt(_decisions.size(), 0, "Events.ai_decision must fire with debug_trace on too")
