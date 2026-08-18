extends GutTest

## Acceptance for #477 — removable-blocker placement (#300). Verifies
## [GraphProcgen.generate] returns a `blockers` array of `{node, size}`
## placements, that the per-tier density is `floor(node_count / denom)`, that
## placements never land on a starter core or a keystone node, that no node is
## picked twice, and that placements are seed-deterministic.

const _KEYSTONE := preload("res://entity/keystone/instances/xp_anchor_keystone.tres")


func _build_config(node_count: int, seed: int) -> GraphProcgenConfig:
	var cfg := GraphProcgenConfig.new()
	cfg.node_count = node_count
	cfg.seed = seed
	cfg.shape_mask = CircularShapeMask.new()
	return cfg


func _generate(cfg: GraphProcgenConfig) -> Dictionary:
	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	return await GraphProcgen.generate(cfg, graph)


func _counts(blockers: Array) -> Dictionary:
	var out := {}
	for placement in blockers:
		var size: int = placement.get("size")
		out[size] = out.get(size, 0) + 1
	return out


func _positions(blockers: Array) -> Array:
	var out := []
	for placement in blockers:
		out.append((placement.get("node") as SkillNode).position)
	return out


func test_density_at_50_nodes() -> void:
	var cfg := _build_config(50, 12345)
	cfg.blocker_per_small = 10
	cfg.blocker_per_medium = 25
	cfg.blocker_per_large = 100
	var result: Dictionary = await _generate(cfg)
	var blockers: Array = result.get("blockers", [])
	var counts := _counts(blockers)
	assert_eq(counts.get(GameRoot.BlockerSize.SMALL, 0), 5, "50/10 = 5 small")
	assert_eq(counts.get(GameRoot.BlockerSize.MEDIUM, 0), 2, "50/25 = 2 medium")
	assert_eq(counts.get(GameRoot.BlockerSize.LARGE, 0), 0, "50/100 = 0 large")
	assert_eq(blockers.size(), 7, "total placements = 5 + 2 + 0")


func test_density_at_100_nodes() -> void:
	var cfg := _build_config(100, 4242)
	cfg.blocker_per_small = 10
	cfg.blocker_per_medium = 25
	cfg.blocker_per_large = 100
	var result: Dictionary = await _generate(cfg)
	var counts := _counts(result.get("blockers", []))
	assert_eq(counts.get(GameRoot.BlockerSize.SMALL, 0), 10, "100/10 = 10 small")
	assert_eq(counts.get(GameRoot.BlockerSize.MEDIUM, 0), 4, "100/25 = 4 medium")
	assert_eq(counts.get(GameRoot.BlockerSize.LARGE, 0), 1, "100/100 = 1 large")


func test_placements_skip_starters_and_keystones() -> void:
	var cfg := _build_config(60, 777)
	var sp := StartingPoint.new()
	sp.position = Vector2.ZERO
	cfg.starting_points.append(sp)
	var kp := KeystonePlacement.new()
	kp.keystone = _KEYSTONE
	cfg.guaranteed_placements.append(kp)

	var result: Dictionary = await _generate(cfg)
	var starting_nodes: Array = result.get("starting_nodes", [])
	assert_eq(starting_nodes.size(), 1, "one manual starter anchor")
	var blockers: Array = result.get("blockers", [])
	assert_gt(blockers.size(), 0, "expected some blocker placements")

	var starter_ids := {}
	for sn in starting_nodes:
		starter_ids[sn.get_instance_id()] = true
	var seen := {}
	for placement in blockers:
		var node: SkillNode = placement.get("node")
		assert_false(starter_ids.has(node.get_instance_id()), "blocker must not be a starter core")
		assert_null(node.keystone, "blocker must not be a keystone node")
		assert_false(seen.has(node.get_instance_id()), "no node picked twice")
		seen[node.get_instance_id()] = true


func test_same_seed_same_placements() -> void:
	var cfg_a := _build_config(80, 9999)
	cfg_a.blocker_per_small = 10
	cfg_a.blocker_per_medium = 25
	cfg_a.blocker_per_large = 100
	var cfg_b := _build_config(80, 9999)
	cfg_b.blocker_per_small = 10
	cfg_b.blocker_per_medium = 25
	cfg_b.blocker_per_large = 100

	var result_a: Dictionary = await _generate(cfg_a)
	var result_b: Dictionary = await _generate(cfg_b)
	assert_eq(
		_positions(result_a.get("blockers", [])), _positions(result_b.get("blockers", [])),
		"same seed must yield identical placements")


func test_denom_zero_disables_tier() -> void:
	var cfg := _build_config(50, 42)
	cfg.blocker_per_small = 0
	cfg.blocker_per_medium = 0
	cfg.blocker_per_large = 0
	var result: Dictionary = await _generate(cfg)
	assert_eq((result.get("blockers", []) as Array).size(), 0, "all denoms 0 → no blockers")

	cfg = _build_config(50, 43)
	cfg.blocker_per_small = 0
	cfg.blocker_per_medium = 5
	cfg.blocker_per_large = 0
	result = await _generate(cfg)
	var counts := _counts(result.get("blockers", []))
	assert_eq(counts.get(GameRoot.BlockerSize.SMALL, 0), 0, "small disabled")
	assert_eq(counts.get(GameRoot.BlockerSize.MEDIUM, 0), 10, "50/5 = 10 medium")
	assert_eq(counts.get(GameRoot.BlockerSize.LARGE, 0), 0, "large disabled")
