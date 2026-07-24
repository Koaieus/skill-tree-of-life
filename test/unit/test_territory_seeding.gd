extends GutTest

## Territory seeding (#275, D-19/D-24). TerritorySeeder loops a shared
## AllocationPolicy (the greedy BFS ball, GreedyBfsBallPolicy) N times to
## grow spawn-time territory via AllocationSystem.force_allocate — the same
## policy shape AIController's frontier picker will reuse at v2, so the
## policy itself never reaches for `graph`; the caller always supplies the
## candidate set.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ENTITY_SCENE := preload("res://entity/entity.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _BALANCED_CORE := preload("res://entity/core/balanced_core.tres")
const _ENEMY_CORE := preload("res://entity/core/basic_enemy_core.tres")
const _SEEDER_TRES := preload("res://procgen/placement/territory_seeder.tres")
const _POLICY_TRES := preload("res://procgen/placement/greedy_bfs_ball.tres")

var _graph: Graph
var _alloc: AllocationSystem


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)


## Builds a `rows` x `cols` grid graph via add_skill_node/add_edge (never the
## containers directly — .claude/rules/graph.md — so graph.navigator mirrors
## it). Returns nodes in row-major order; node 0 (top-left) is the intended
## core, giving generous branching for BFS-ball frontier growth.
func _build_grid(g: Graph, rows: int, cols: int) -> Array[SkillNode]:
	var grid: Dictionary = {}
	var nodes: Array[SkillNode] = []
	for r in rows:
		for c in cols:
			var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
			sn.name = "N_%d_%d" % [r, c]
			sn.position = Vector2(c * 96.0, r * 96.0)
			g.add_skill_node(sn)
			grid[Vector2i(r, c)] = sn
			nodes.append(sn)
	for r in rows:
		for c in cols:
			var a: SkillNode = grid[Vector2i(r, c)]
			if c + 1 < cols:
				g.add_edge(a, grid[Vector2i(r, c + 1)])
			if r + 1 < rows:
				g.add_edge(a, grid[Vector2i(r + 1, c)])
	return nodes


func _make_entity(g: Graph, core_class: CoreClass) -> Entity:
	var e := _ENTITY_SCENE.instantiate() as Entity
	e.stat_board = _BOARD.duplicate(true) as StatBoard
	e.core_class = core_class
	g.entities_container.add_child(e)
	return e


func _rng(value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = value
	return r


## Fresh seeder + policy per call so parallel `_build_grid` fixtures within
## one test never share RNG state through a cached resource.
func _new_seeder() -> TerritorySeeder:
	var seeder := _SEEDER_TRES.duplicate(true) as TerritorySeeder
	seeder.policy = _POLICY_TRES.duplicate(true) as AllocationPolicy
	return seeder


func _owned_reachable_from_core(entity: Entity, g: Graph, core: SkillNode) -> int:
	var visited: Dictionary[SkillNode, bool] = {core: true}
	var frontier: Array[SkillNode] = [core]
	while not frontier.is_empty():
		var next: Array[SkillNode] = []
		for n in frontier:
			for nb in g.get_neighbours(n):
				if nb.owned_by == entity and not visited.has(nb):
					visited[nb] = true
					next.append(nb)
		frontier = next
	return visited.size()


# ── 1. exact count ───────────────────────────────────────────────────────

func test_seeding_yields_exactly_n_owned_nodes() -> void:
	var nodes := _build_grid(_graph, 6, 6)
	var entity := _make_entity(_graph, _ENEMY_CORE)
	await get_tree().process_frame
	_alloc.force_allocate(entity, nodes[0])
	entity.core_location = nodes[0]

	var seeder := _new_seeder()
	var achieved := seeder.seed_territory(entity, _graph, _alloc, 20, _rng(1))

	assert_eq(achieved, 20, "seed_territory should report 20 claimed")
	assert_eq(entity.navigator.get_mirrored_nodes().size(), 20,
			"entity should own exactly 20 nodes, core included")


# ── 2. connected / island-free ──────────────────────────────────────────

func test_seeded_territory_is_connected_to_core() -> void:
	var nodes := _build_grid(_graph, 6, 6)
	var entity := _make_entity(_graph, _ENEMY_CORE)
	await get_tree().process_frame
	_alloc.force_allocate(entity, nodes[0])
	entity.core_location = nodes[0]

	var seeder := _new_seeder()
	seeder.seed_territory(entity, _graph, _alloc, 20, _rng(7))

	var owned_total := entity.navigator.get_mirrored_nodes().size()
	var reachable := _owned_reachable_from_core(entity, _graph, nodes[0])
	assert_eq(reachable, owned_total,
			"every owned node must be reachable from the core through owned nodes only")


# ── 3. determinism ───────────────────────────────────────────────────────

func test_same_seed_yields_identical_territory() -> void:
	var graph_a := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph_a)
	var alloc_a := AllocationSystem.new()
	alloc_a.graph = graph_a
	add_child_autofree(alloc_a)
	var nodes_a := _build_grid(graph_a, 6, 6)
	var entity_a := _make_entity(graph_a, _ENEMY_CORE)
	await get_tree().process_frame
	await get_tree().process_frame
	alloc_a.force_allocate(entity_a, nodes_a[0])
	entity_a.core_location = nodes_a[0]
	_new_seeder().seed_territory(entity_a, graph_a, alloc_a, 20, _rng(42))

	var graph_b := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph_b)
	var alloc_b := AllocationSystem.new()
	alloc_b.graph = graph_b
	add_child_autofree(alloc_b)
	var nodes_b := _build_grid(graph_b, 6, 6)
	var entity_b := _make_entity(graph_b, _ENEMY_CORE)
	await get_tree().process_frame
	await get_tree().process_frame
	alloc_b.force_allocate(entity_b, nodes_b[0])
	entity_b.core_location = nodes_b[0]
	_new_seeder().seed_territory(entity_b, graph_b, alloc_b, 20, _rng(42))

	var names_a: Array[String] = []
	for n in entity_a.navigator.get_mirrored_nodes():
		names_a.append(n.name)
	names_a.sort()

	var names_b: Array[String] = []
	for n in entity_b.navigator.get_mirrored_nodes():
		names_b.append(n.name)
	names_b.sort()

	assert_eq(names_a, names_b, "identical seed must produce identical territory")


# ── 4. player regression guard (D-16) ───────────────────────────────────

func test_player_style_seeding_with_node_count_one_adds_nothing() -> void:
	var nodes := _build_grid(_graph, 6, 6)
	var entity := _make_entity(_graph, _BALANCED_CORE)
	await get_tree().process_frame
	_alloc.force_allocate(entity, nodes[0])
	entity.core_location = nodes[0]

	var seeder := _new_seeder()
	var achieved := seeder.seed_territory(entity, _graph, _alloc, 1, _rng(3))

	assert_eq(achieved, 1, "node_count == 1 (core only) must not expand further")
	assert_eq(entity.navigator.get_mirrored_nodes().size(), 1,
			"player must own only its core node")


# ── 5. enemy level == claimed node count (D-19) ─────────────────────────

func test_enemy_level_matches_seeded_node_count() -> void:
	var nodes := _build_grid(_graph, 6, 6)
	var entity := _make_entity(_graph, _ENEMY_CORE)
	await get_tree().process_frame
	_alloc.force_allocate(entity, nodes[0])
	entity.core_location = nodes[0]

	var seeder := _new_seeder()
	var achieved := seeder.seed_territory(entity, _graph, _alloc, 20, _rng(9))
	entity.level = achieved

	assert_eq(achieved, 20)
	assert_eq(entity.level, 20, "D-19: enemy_level == starting_nodes")


# ── 6. elevated enemy WIS grants xp_per_turn == WIS // 2 (D-19, non-territorial) ─

func test_enemy_core_grants_elevated_wis_and_matching_xp_per_turn() -> void:
	var entity := _make_entity(_graph, _ENEMY_CORE)
	await get_tree().process_frame

	assert_eq(entity.stat_board.wisdom.value, 80,
			"basic_enemy_core should grant elevated WIS (TBD #268 placeholder)")
	assert_eq(entity.stat_board.xp_per_turn.value, 40,
			"xp_per_turn should track WIS // 2 (D-15) for the granted WIS")
	assert_gt(entity.stat_board.xp_per_turn.value, 10,
			"elevated-WIS enemy income must exceed the pinned baseline of 10")


# ── 7. graceful exhaustion ───────────────────────────────────────────────

func test_seeding_stops_gracefully_when_graph_runs_out() -> void:
	var nodes := _build_grid(_graph, 2, 3)  # 6 nodes total
	var entity := _make_entity(_graph, _ENEMY_CORE)
	await get_tree().process_frame
	_alloc.force_allocate(entity, nodes[0])
	entity.core_location = nodes[0]

	var seeder := _new_seeder()
	var achieved := seeder.seed_territory(entity, _graph, _alloc, 20, _rng(5))

	assert_eq(achieved, 6, "should claim every reachable node and stop, not hang")
	assert_eq(entity.navigator.get_mirrored_nodes().size(), 6)


# ── 8. policy never picks outside the supplied candidates ──────────────

func test_policy_pick_next_never_leaves_supplied_candidates() -> void:
	var nodes := _build_grid(_graph, 6, 6)
	var entity := _make_entity(_graph, _ENEMY_CORE)
	await get_tree().process_frame
	_alloc.force_allocate(entity, nodes[0])
	entity.core_location = nodes[0]

	# Deliberately restrict candidates to 3 nodes out of the 36-node graph —
	# the fog-of-war seam (D-24): the policy must never reach past what it's
	# handed, even though the wider graph has plenty of other unowned nodes.
	var restricted: Array[SkillNode] = [nodes[10], nodes[17], nodes[23]]
	var policy := _POLICY_TRES.duplicate(true) as AllocationPolicy
	var rng := _rng(11)

	for _i in 50:
		policy.rng = rng
		var pick := policy.pick_next(entity, restricted, null)
		assert_true(restricted.has(pick),
				"pick_next must only ever return a node from the supplied candidates")
