@tool
extends GutTest

## #385: NodeHighlightOverlay._draw() calls get_node_role(sn) once PER NODE
## PER REPAINT. With a hop-based spell source selected, the old code routed
## every one of those through Targeting.is_valid_target -> HopRangeFinder.in_range,
## which runs one AStar query (astar.get_id_path) per candidate — an N-node
## repaint was N graph traversals. MagicAttackPlan caches its valid-target set
## off RangeFinder.gather traversals instead.
##
## Asserted with a call-counting spy on the mirror's `nodes_within` (what
## HopRangeFinder.gather calls) — never on ownership internals.
##
## [b]Re-pointed for #728.[/b] The source is no longer clicked, so "one repaint,
## one traversal" is now stated per ELIGIBLE CASTER: the union runs one bounded
## BFS per owned node that can cast the spell, and a repaint costs that many, not
## one per graph node. #385's original claim survives verbatim in
## [method test_a_repaint_performs_exactly_one_graph_traversal] (this fixture
## owns exactly one caster) and in the unchanged-repaint test; the old
## "changing source" test is replaced by the two things #728 actually promises —
## that hovering does NOT invalidate, and that an ownership change does.

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
var _alloc: AllocationSystem


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
	# Through the AllocationSystem, not a bare `owned_by =`: #728 reads the
	# eligible-caster set off `attacker.navigator`, which only a real allocation
	# populates (see .claude/rules/graph.md).
	_alloc = autofree(AllocationSystem.new())
	_alloc.graph = _graph
	_graph.add_child(_alloc)
	_alloc.force_allocate(_attacker, _source)

	var targeting := NodeTargeting.new()
	targeting.ownership_filter = SkillNode.Ownership.HOSTILE
	targeting.range_finder = HopRangeFinder.new()
	(targeting.range_finder as HopRangeFinder).max_hops = 3

	var spell := SpellDef.new()
	spell.targeting = targeting
	# A hub owned alone has owned-subgraph degree 0, so SpellDef's default
	# min_degree = 1 would leave no eligible caster at all. This test measures
	# traversals, not gating.
	spell.min_degree = 0

	_plan = autofree(MagicAttackPlan.new())
	_plan.attacker = _attacker
	_plan.spell = spell


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


func test_a_repaint_performs_exactly_one_graph_traversal() -> void:
	assert_eq(_spy.call_count, 0, "arming the plan alone must not traverse yet — lazy rebuild")

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


## #728 acceptance: "changing the hovered target does not invalidate the union".
## The union rides its OWN dirty flag precisely so it can survive a hover — the
## older per-source cache is invalidated by `state_changed`, which every hover
## emits, and reusing that flag would re-walk the graph on mouse movement.
func test_hovering_a_new_candidate_does_not_reinvalidate_the_union() -> void:
	for n in _graph.get_skill_nodes():
		_plan.get_node_role(n)
	assert_eq(_spy.call_count, 1)

	for n in _nodes:
		_plan.set_hover_target(n)
		for other in _graph.get_skill_nodes():
			_plan.get_node_role(other)

	assert_eq(_spy.call_count, 1,
			"moving the cursor across every node must not re-walk the graph even once")


## The other half: an ownership change DOES invalidate, and the extra traversal
## is per newly-eligible caster. Allocating a spoke gives the attacker a second
## owned node — and gives BOTH nodes owned-subgraph degree 1, so this also pins
## that the union re-reads eligibility rather than caching a source list.
func test_an_ownership_change_invalidates_and_costs_one_traversal_per_caster() -> void:
	for n in _graph.get_skill_nodes():
		_plan.get_node_role(n)
	assert_eq(_spy.call_count, 1)

	_alloc.force_allocate(_attacker, _nodes[0])
	_plan.invalidate_union()  # BattleSystem pushes this off AllocationSystem's signals
	assert_eq(_spy.call_count, 1, "invalidating alone must not traverse yet — still lazy")

	for n in _graph.get_skill_nodes():
		_plan.get_node_role(n)
	assert_eq(_spy.call_count, 3, "two eligible casters, one bounded BFS each")
