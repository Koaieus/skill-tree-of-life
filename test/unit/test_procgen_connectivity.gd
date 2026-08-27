extends GutTest

## Acceptance for #339 ① — the procgen connectivity certificate. The skill
## tree must be ONE connected component, and that today rests on the Kruskal
## pass in GraphProcgen._triangulate_and_prune spanning every node by
## construction. This test verifies it independently over the emitted graph:
## union-find over every real edge (self-loops excluded) must yield exactly
## one component.

const _PRESET_PATH := "res://procgen/presets/first_level/first_level.tres"


func test_first_level_graph_is_one_component() -> void:
	var cfg_src: GraphProcgenConfig = load(_PRESET_PATH)
	var cfg: GraphProcgenConfig = cfg_src.duplicate(true)
	# #349: topology is a top-level module .tres (ExtResource); duplicate(true)
	# does not cross that boundary, so re-duplicate before mutating (acceptance 4).
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = 120
	cfg.n_random_starters = 0
	cfg.seed = 42

	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame

	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	var nodes: Array = result.get("nodes", [])
	assert_gt(nodes.size(), 80, "sanity: got %d nodes; expected close to 120" % nodes.size())

	# Union-find over the emitted edges (skip self-loops — edge.from == edge.to).
	var parent := {}
	for n in nodes:
		parent[n] = n
	var find := func(x: Object) -> Object:
		while parent[x] != x:
			parent[x] = parent[parent[x]]
			x = parent[x]
		return x
	for e in graph.get_edges():
		if e.from == e.to:
			continue
		var ra: Object = find.call(e.from)
		var rb: Object = find.call(e.to)
		if ra != rb:
			parent[ra] = rb

	var roots := {}
	for n in nodes:
		roots[find.call(n)] = true
	assert_eq(roots.size(), 1,
			"expected exactly 1 connected component, got %d" % roots.size())
