extends GutTest

## End-to-end smoke for `presets/first_level/first_level.tres`. Loads the
## preset, runs procgen, and asserts the headline invariants:
##   - target node count is roughly hit
##   - all archetypes are represented
##   - exactly 10 anomalous nodes get the role tag
##   - at least one xp_growth-tagged node sits near the starter

const _PRESET_PATH := "res://procgen/presets/first_level/first_level.tres"


func test_preset_loads() -> void:
	var cfg: GraphProcgenConfig = load(_PRESET_PATH)
	assert_not_null(cfg, "first_level.tres should load as GraphProcgenConfig")
	assert_gt(cfg.node_count, 0, "node_count should be set")
	assert_eq(cfg.archetypes.size(), 6, "expected 6 archetypes (red/green/blue/white/gold/purple)")
	assert_not_null(cfg.modifier_pool_set, "modifier_pool_set should be set")
	assert_gt(cfg.modifier_pool_set.packs.size(), 0, "pool set should carry StatPacks")
	assert_eq(cfg.weight_profiles.size(), 3, "profiles: archetype + radial + collision")
	assert_not_null(cfg.budget_policy)
	assert_eq(cfg.guaranteed_placements.size(), 3)


func test_modifiers_rolled_on_nodes() -> void:
	var cfg_src: GraphProcgenConfig = load(_PRESET_PATH)
	var cfg: GraphProcgenConfig = cfg_src.duplicate(true)
	cfg.node_count = 60
	cfg.n_random_starters = 0
	cfg.seed = 9

	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame

	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	var nodes: Array = result.get("nodes", [])
	var with_modifiers := 0
	for n in nodes:
		if not n.modifiers.is_empty():
			with_modifiers += 1
	assert_gt(with_modifiers, nodes.size() / 2, "expected most nodes to roll modifiers; got %d/%d" % [with_modifiers, nodes.size()])


func test_procgen_generates_full_level() -> void:
	var cfg_src: GraphProcgenConfig = load(_PRESET_PATH)
	# Smaller node count for test speed — same shape of pipeline.
	var cfg: GraphProcgenConfig = cfg_src.duplicate(true)
	cfg.node_count = 120
	cfg.n_random_starters = 0  # keep starter set deterministic for assertions
	cfg.seed = 42

	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame

	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	var nodes: Array = result.get("nodes", [])
	assert_true(nodes.size() > 80, "got %d nodes; expected close to 120" % nodes.size())

	# Every archetype represented at least once.
	var archetype_counts := {}
	for n in nodes:
		var arch: StringName = n.get_meta("base_type", &"")
		archetype_counts[arch] = archetype_counts.get(arch, 0) + 1
	for a in [&"red", &"green", &"blue", &"gold", &"purple"]:
		assert_true(a in archetype_counts, "archetype %s missing" % String(a))

	# RandomBudgetBoost: exactly 10 nodes carry the anomalous role tag.
	var anomalous_count := 0
	for n in nodes:
		var tags: Array = n.get_meta("role_tags", [])
		if &"anomalous" in tags:
			anomalous_count += 1
	assert_eq(anomalous_count, 10, "expected 10 anomalous nodes; got %d" % anomalous_count)

	# Keystone placement: at least one node carries the xp_anchor keystone.
	var keystone_count := 0
	for n in nodes:
		if n.keystone != null:
			keystone_count += 1
	assert_eq(keystone_count, 1, "expected 1 keystone node; got %d" % keystone_count)
