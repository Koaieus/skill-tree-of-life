@tool
extends GutTest

## #385: NodeHighlightOverlay._draw() calls get_node_role(sn) once PER NODE
## PER REPAINT. With a hop-based spell source selected, the old code routed
## every one of those through Targeting.is_valid_target -> HopRangeFinder.in_range,
## which runs one AStar query (astar.get_id_path) per candidate — an N-node
## repaint was N graph traversals. MagicAttackPlan now caches its valid-target
## set off ONE RangeFinder.gather traversal, invalidated by state_changed.
##
## This is the acceptance test the issue names: a repaint performs EXACTLY ONE
## graph traversal. Asserted with a call-counting spy on the mirror's
## `nodes_within` (what HopRangeFinder.gather calls) — never on ownership
## internals.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")

## Counts calls to `nodes_within` — the one BFS traversal `HopRangeFinder.gather`
## performs. `Navigator._should_mirror` falls through to the base default
## (mirrors everything), so this stands in for the real global navigator.
class CountingNavigator extends Navigator:
	var call_count := 0

	func nodes_within(source: SkillNode, max_hops: int) -> Dictionary[SkillNode, int]:
		call_count += 1
		return super.nodes_within(source, max_hops)


var _graph: Graph
var _spy: CountingNavigator
var _attacker: Entity
var _source: SkillNode
var _nodes: Array[SkillNode]
var _plan: MagicAttackPlan


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	# A small hub-and-spoke graph: source + N leaves within hop range.
	_source = autofree(_SKILL_NODE_SCENE.instantiate())
	_graph.add_skill_node(_source)
	_nodes = []
	for i in 12:
		var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
		_graph.add_skill_node(n)
		_add_edge(_source, n)
		_nodes.append(n)

	# Swap in the counting spy AFTER the graph is populated, so its wire_to
	# seed sweep mirrors every node already present, matching the real
	# Navigator's coverage.
	_spy = CountingNavigator.new()
	_spy.graph = _graph
	add_child_autofree(_spy)
	_spy.wire_to(_graph)
	_graph.navigator = _spy

	_attacker = autofree(Entity.new())
	_attacker.faction = _PLAYER_FACTION
	_graph.add_child(_attacker)
	await get_tree().process_frame  # entity._ready wires attacker.navigator
	_source.owned_by = _attacker

	var targeting := NodeTargeting.new()
	targeting.ownership_filter = SkillNode.Ownership.HOSTILE
	targeting.range_finder = HopRangeFinder.new()
	(targeting.range_finder as HopRangeFinder).max_hops = 3

	var spell := SpellDef.new()
	spell.targeting = targeting

	_plan = autofree(MagicAttackPlan.new())
	_plan.attacker = _attacker
	_plan.spell = spell
	_plan._on_node_left_clicked(_source)  # picks the source, emits state_changed


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


func test_a_repaint_performs_exactly_one_graph_traversal() -> void:
	assert_eq(_spy.call_count, 0, "picking the source alone must not traverse yet — lazy rebuild")

	# Simulate NodeHighlightOverlay._draw(): get_node_role for every node,
	# exactly as it iterates graph.get_skill_nodes() once per repaint.
	for n in _graph.get_skill_nodes():
		_plan.get_node_role(n)

	assert_eq(_spy.call_count, 1,
			"one repaint over N nodes must cost exactly one traversal, not one per node")


func test_a_second_repaint_with_no_state_change_costs_nothing_more() -> void:
	for n in _graph.get_skill_nodes():
		_plan.get_node_role(n)
	assert_eq(_spy.call_count, 1)

	for n in _graph.get_skill_nodes():
		_plan.get_node_role(n)
	assert_eq(_spy.call_count, 1, "the cache survives an unchanged repaint — still one traversal total")


func test_changing_source_invalidates_and_costs_one_more_traversal() -> void:
	for n in _graph.get_skill_nodes():
		_plan.get_node_role(n)
	assert_eq(_spy.call_count, 1)

	var new_source := _nodes[0]
	new_source.owned_by = _attacker
	_plan.pop()  # clear the old source — re-sourcing is pop-then-push, not a direct swap
	_plan._on_node_left_clicked(new_source)
	assert_eq(_spy.call_count, 1, "picking a new source alone must not traverse yet")

	for n in _graph.get_skill_nodes():
		_plan.get_node_role(n)
	assert_eq(_spy.call_count, 2, "a repaint after the source changed rebuilds exactly once more")
