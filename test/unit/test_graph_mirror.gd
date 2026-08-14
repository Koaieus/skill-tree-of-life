extends GutTest

## [GraphMirror] is the degree AUTHORITY that `.claude/rules/degree.md` routes
## every caller to, and it had no test of its own (audit triage C24). These
## cover the two things the 2026-08-14 audit changed in it — the degree
## definition used by `get_nodes_by_degree`, and `mirror_add`'s edge lookup —
## plus enough of the surrounding contract that the next edit has something to
## break.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")

var _graph: Graph


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)


func _add_nodes(count: int) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for i in count:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		out.append(sn)
	return out


func _connect(a: SkillNode, b: SkillNode) -> Edge:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)
	return e


## Mirrors everything — the base `_should_mirror` — so these tests are about
## GraphMirror itself, not EntityNavigator's ownership filter.
func _mirror_all(nodes: Array[SkillNode]) -> GraphMirror:
	var m := GraphMirror.new()
	autofree(m)
	m.graph = _graph
	for n in nodes:
		m.mirror_add(n)
	return m


func test_mirror_add_connects_both_endpoints_of_an_existing_edge() -> void:
	var n := _add_nodes(3)
	_connect(n[0], n[1])
	_connect(n[1], n[2])
	await get_tree().process_frame

	var m := _mirror_all(n)
	assert_eq(m.get_degree(n[0]), 1)
	assert_eq(m.get_degree(n[1]), 2, "the middle node sees both its edges")
	assert_eq(m.get_degree(n[2]), 1)


## `mirror_add` connects only to endpoints ALREADY mirrored, so a partial
## mirror must not invent a connection to a node outside it. This is the
## property that makes an EntityNavigator an induced subgraph of the owned
## territory rather than a neighbourhood of it.
func test_mirror_add_ignores_edges_to_unmirrored_nodes() -> void:
	var n := _add_nodes(3)
	_connect(n[0], n[1])
	_connect(n[1], n[2])
	await get_tree().process_frame

	var m := _mirror_all([n[0], n[1]] as Array[SkillNode])
	assert_eq(m.get_degree(n[1]), 1, "the edge to the unmirrored n2 is not mirrored")
	assert_eq(m.get_degree(n[2]), -1, "an unmirrored node has no degree at all")


## A self-loop is +2, and `get_nodes_by_degree` must agree with `get_degree`
## about that. It did not until 2026-08-14: it read a bare
## `astar.get_point_connections().size()`, which AStar cannot represent a
## self-loop in at all, so a self-looped node reported one degree to
## `get_degree` and another to every degree QUERY on the same class.
func test_degree_queries_agree_with_get_degree_on_self_loops() -> void:
	var n := _add_nodes(2)
	_connect(n[0], n[1])
	_connect(n[1], n[1])  # self-loop on the middle-ish node
	await get_tree().process_frame

	var m := _mirror_all(n)
	assert_eq(m.get_degree(n[1]), 3, "one edge + a self-loop counting twice")
	assert_true(m.get_nodes_by_degree(3).has(n[1]),
		"get_nodes_by_degree must use the same degree definition as get_degree")
	assert_false(m.get_nodes_by_degree(1).has(n[1]),
		"and must NOT still report the self-looped node at its AStar-only degree")


## The consumer that motivates the above: RangedAttackPlan targets
## `navigator.get_leaf_nodes()`. A node holding a self-loop is not a leaf.
func test_a_self_looped_node_is_not_a_leaf() -> void:
	var n := _add_nodes(2)
	_connect(n[0], n[1])
	_connect(n[0], n[0])
	await get_tree().process_frame

	var m := _mirror_all(n)
	var leaves := m.get_leaf_nodes()
	assert_true(leaves.has(n[1]), "the plain endpoint is a leaf")
	assert_false(leaves.has(n[0]), "the self-looped one is degree 3, not 1")


func test_mirror_add_is_idempotent() -> void:
	var n := _add_nodes(2)
	_connect(n[0], n[1])
	await get_tree().process_frame

	var m := _mirror_all(n)
	m.mirror_add(n[0])
	m.mirror_add(n[0])
	assert_eq(m.get_mirrored_nodes().size(), 2, "re-adding mints no second vertex")
	assert_eq(m.get_degree(n[0]), 1, "and no duplicate connection")
