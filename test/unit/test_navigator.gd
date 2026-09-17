extends GutTest

## `Navigator` (the base `GraphMirror` wired to every `Graph.tscn`'s
## `$Navigator`, per graph.gd:25) had never been instantiated in a test —
## it only appeared in comments explaining why other fixtures bypass it
## (test_node_regen.gd, test_aura_effect.gd). These exercise the SCENE's real
## Navigator (`graph.navigator`), with no Entity/AllocationSystem/aura
## scaffolding involved, so coverage matches what production code actually
## gets.
##
## Populate via Graph.add_skill_node / Graph.add_edge only — the containers
## don't emit signals, so graph.navigator never mirrors a direct child add
## and every query would silently return empty. See .claude/rules/graph.md.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

var _graph: Graph


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	await get_tree().process_frame  # Navigator._ready wires to the graph


func _add_node(pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.global_position = pos
	_graph.add_skill_node(sn)
	return sn


func test_navigator_mirrors_nodes_and_edges_with_no_entity_or_aura_scaffolding() -> void:
	var a := _add_node(Vector2(0, 0))
	var b := _add_node(Vector2(10, 0))
	_graph.add_edge(a, b)
	await get_tree().process_frame

	var mirrored := _graph.navigator.get_mirrored_nodes()
	assert_true(mirrored.has(a), "a is mirrored")
	assert_true(mirrored.has(b), "b is mirrored")
	assert_eq(_graph.navigator.get_degree(a), 1)
	assert_eq(_graph.navigator.get_degree(b), 1)


## The Navigator is already wired (before_each awaited its own `_ready`)
## before this node is even created — this is the "added after the navigator
## exists" case the issue calls out.
func test_node_added_after_navigator_already_exists_is_picked_up() -> void:
	var late := _add_node(Vector2(50, 50))
	await get_tree().process_frame

	assert_true(_graph.navigator.get_mirrored_nodes().has(late))
	assert_ne(_graph.navigator.vertex_id(late), -1)


func test_navigator_bookkeeping_follows_removal() -> void:
	var a := _add_node(Vector2(0, 0))
	var b := _add_node(Vector2(10, 0))
	_graph.add_edge(a, b)
	await get_tree().process_frame

	# `remove_skill_node` fires `node_removed` (and Navigator's mirror_remove)
	# synchronously, before its own `queue_free()` — don't await a frame here,
	# or `b` is already a freed object by the time these assertions run.
	_graph.remove_skill_node(b)

	assert_false(_graph.navigator.get_mirrored_nodes().has(b))
	assert_eq(_graph.navigator.vertex_id(b), -1)
	assert_eq(_graph.navigator.get_degree(a), 0, "a's edge to the removed node is gone too")
	await get_tree().process_frame  # let the deferred queue_free land before teardown


## Regression pin for the documented adjacency-cache hole
## (.claude/rules/graph.md): the cache invalidates on child add/remove, NOT on
## an `Edge.from`/`to` reassignment on an already-parented edge. Navigator's
## own edge wiring rides on `Graph`'s `edge_added`/`edge_removed` signals
## (fired once, at add-time), so it has the identical blind spot. If this
## test starts failing, `_mark_adjacency_dirty()` (or an equivalent Navigator
## fix) learned to react to endpoint reassignment — update the rule doc to
## match rather than "fixing" this test.
func test_reassigning_a_parented_edges_endpoints_does_not_update_the_mirror() -> void:
	var a := _add_node(Vector2(0, 0))
	var b := _add_node(Vector2(10, 0))
	var c := _add_node(Vector2(20, 0))
	var edge := _graph.add_edge(a, b)
	await get_tree().process_frame

	assert_eq(_graph.navigator.get_degree(a), 1)
	assert_eq(_graph.navigator.get_degree(c), 0)
	# Force Graph's adjacency cache to build NOW, while the edge still points
	# a→b, so the reassignment below is a genuine "stale cache" scenario
	# rather than a first-ever build that would just read the new endpoints.
	assert_true(_graph.get_neighbours(a).has(b), "cache built while the edge is still a→b")

	edge.to = c  # re-point b→c on the already-parented edge; no add/remove
	await get_tree().process_frame

	assert_eq(_graph.navigator.get_degree(c), 0,
			"the mirror still doesn't know about the re-pointed edge — pinned limitation")
	assert_true(_graph.get_neighbours(a).has(b),
			"Graph's own adjacency cache is equally stale here, per .claude/rules/graph.md")


# ── Adjacency queries (#940) ───────────────────────────────────────────────
# `are_adjacent` / `neighbours_of` are THE adjacency check — the mirror that
# holds the AStar answers it, instead of callers flooding `nodes_within(..., 1)`
# or building a neighbour Array to `.has()` one bool out of it.

const _BOARD := preload("res://entity/default_entity_board.tres")


## An Entity under the graph gets its own EntityNavigator from `initialize()`;
## ownership is written directly and mirrored by hand, the same calls
## AllocationSystem.force_allocate makes (the mutation contract in
## entity_navigator.gd).
func _entity_owning(nodes: Array[SkillNode]) -> Entity:
	var e := autofree(Entity.new()) as Entity
	e.display_name = "Owner"
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(e)
	await get_tree().process_frame
	for n in nodes:
		n.owned_by = e
		e.navigator.mirror_add(n)
	return e


func test_are_adjacent_is_true_across_a_real_edge_and_false_two_hops_apart() -> void:
	var a := _add_node(Vector2(0, 0))
	var b := _add_node(Vector2(10, 0))
	var c := _add_node(Vector2(20, 0))
	_graph.add_edge(a, b)
	_graph.add_edge(b, c)
	await get_tree().process_frame

	var nav := _graph.navigator
	assert_true(nav.are_adjacent(a, b), "a-b share an edge")
	assert_true(nav.are_adjacent(b, a), "adjacency is symmetric")
	assert_false(nav.are_adjacent(a, c), "a and c are two hops apart")
	assert_false(nav.are_adjacent(a, null), "null is never adjacent")


func test_are_adjacent_is_false_for_a_node_and_itself_even_with_a_self_loop() -> void:
	var a := _add_node(Vector2(0, 0))
	var b := _add_node(Vector2(10, 0))
	_graph.add_edge(a, b)
	_graph.add_edge(a, a)  # self-loop: a propagation/render edge, never a hop
	await get_tree().process_frame

	assert_false(_graph.navigator.are_adjacent(a, a), "a self-loop is not adjacency")
	assert_true(_graph.navigator.are_adjacent(a, b), "the real edge still counts")


func test_are_adjacent_is_false_for_an_unmirrored_node_on_an_entity_navigator() -> void:
	var a := _add_node(Vector2(0, 0))
	var b := _add_node(Vector2(10, 0))
	_graph.add_edge(a, b)
	await get_tree().process_frame
	var e: Entity = await _entity_owning([a] as Array[SkillNode])

	assert_true(_graph.navigator.are_adjacent(a, b), "the whole-board mirror sees the edge")
	assert_false(e.navigator.are_adjacent(a, b), "b is not in the territory, so not adjacent there")
	assert_false(e.navigator.are_adjacent(b, a), "either way round")


func test_neighbours_of_on_an_entity_navigator_returns_only_owned_neighbours_never_self() -> void:
	# hub h with owned neighbours o1, o2, an unowned neighbour u, and a self-loop.
	var h := _add_node(Vector2(0, 0))
	var o1 := _add_node(Vector2(10, 0))
	var o2 := _add_node(Vector2(-10, 0))
	var u := _add_node(Vector2(0, 10))
	var far := _add_node(Vector2(30, 0))
	_graph.add_edge(h, o1)
	_graph.add_edge(h, o2)
	_graph.add_edge(h, u)
	_graph.add_edge(h, h)
	_graph.add_edge(o1, far)
	await get_tree().process_frame
	var e: Entity = await _entity_owning([h, o1, o2, far] as Array[SkillNode])

	var got := e.navigator.neighbours_of(h)
	assert_eq(got.size(), 2, "exactly the two owned neighbours")
	assert_true(got.has(o1) and got.has(o2), "o1 and o2, as a set")
	assert_false(got.has(u), "the unowned neighbour is not in the territory")
	assert_false(got.has(h), "never the node itself, self-loop or not")
	assert_false(got.has(far), "two hops is not a neighbour")

	var board := _graph.navigator.neighbours_of(h)
	assert_eq(board.size(), 3, "the whole-board mirror sees u as well")
	assert_true(board.has(u))
	assert_eq(_graph.navigator.neighbours_of(null).size(), 0, "null → empty")
	assert_eq(e.navigator.neighbours_of(u).size(), 0, "unmirrored → empty")


# ── borders (#941) ─────────────────────────────────────────────────────────
# "Does this node touch my territory?" — asked of the territory's own mirror:
# not mirrored here, and at least one whole-board neighbour is. Membership,
# never `owned_by == entity` (.claude/rules/ownership-vocabulary.md).

func test_borders_is_true_for_an_unowned_node_with_one_owned_neighbour() -> void:
	var o := _add_node(Vector2(0, 0))
	var u := _add_node(Vector2(10, 0))
	var lone := _add_node(Vector2(50, 50))
	_graph.add_edge(o, u)
	await get_tree().process_frame
	var e: Entity = await _entity_owning([o] as Array[SkillNode])

	assert_true(e.navigator.borders(u), "u is unowned and touches the owned o")
	assert_false(e.navigator.borders(lone), "no owned neighbour → does not border")


func test_borders_is_false_for_an_owned_node_even_with_owned_neighbours() -> void:
	var a := _add_node(Vector2(0, 0))
	var b := _add_node(Vector2(10, 0))
	_graph.add_edge(a, b)
	await get_tree().process_frame
	var e: Entity = await _entity_owning([a, b] as Array[SkillNode])

	assert_false(e.navigator.borders(a), "inside the territory is not its border")
	assert_false(e.navigator.borders(b))


func test_borders_is_false_for_null_and_for_a_node_the_graph_never_mirrored() -> void:
	var o := _add_node(Vector2(0, 0))
	await get_tree().process_frame
	var e: Entity = await _entity_owning([o] as Array[SkillNode])
	# Added straight into the container: no node_added, the board Navigator
	# never saw it, so it has no neighbourhood to ask about.
	var ghost := _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(ghost)

	assert_false(e.navigator.borders(null), "null never borders")
	assert_false(e.navigator.borders(ghost), "unmirrored-in-graph never borders")


func test_borders_is_true_for_a_hostile_owned_node_touching_the_territory() -> void:
	# The AiRecon reader: another entity's node next to mine is a door.
	var mine := _add_node(Vector2(0, 0))
	var theirs := _add_node(Vector2(10, 0))
	_graph.add_edge(mine, theirs)
	await get_tree().process_frame
	var me: Entity = await _entity_owning([mine] as Array[SkillNode])
	var them: Entity = await _entity_owning([theirs] as Array[SkillNode])

	assert_true(me.navigator.borders(theirs), "their node touches my territory")
	assert_true(them.navigator.borders(mine), "and mine touches theirs")
