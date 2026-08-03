extends GutTest

## Acceptance for #42 — the 4-tier floor-guaranteed staged self-loop draw
## in GraphProcgen. Replaces the naive per-node `randf() < self_loop_rate`
## roll. The floors are the contract: at the default tier knobs
## (0.10 / 0.17 / 0.30 / 0.30) a 300-node map MUST show the rarity ladder
## (≥30 single loops, ≥5 doubles, ≥1 triple, none beyond the cap of 4), and
## the ladder scales linearly to 3000 (≥300 / ≥51 / ≥15 / ≥4).

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


func _loop_counts(nodes: Array) -> Array[int]:
	var out: Array[int] = []
	for n in nodes:
		out.append((n as SkillNode).self_loop_count)
	return out


## One floor assertion: at least `floor` nodes carry >= `min_loops` self-loops.
func _assert_floor(counts: Array[int], min_loops: int, floor: int, context: String) -> void:
	var actual := 0
	for c in counts:
		if c >= min_loops:
			actual += 1
	assert_true(
		actual >= floor,
		"%s: expected >= %d nodes with >= %d self-loop(s), got %d"
				% [context, floor, min_loops, actual])


## The number of tier knobs IS the cap (4): no node may exceed it.
func _assert_cap(counts: Array[int], context: String) -> void:
	var over := 0
	for c in counts:
		if c > 4:
			over += 1
	assert_eq(over, 0, "%s: cap is 4 — %d node(s) exceed it" % [context, over])


func test_default_knobs_hit_floors_at_300() -> void:
	var result: Dictionary = await _generate(_build_config(300, 12345))
	var counts := _loop_counts(result.get("nodes", []))
	assert_eq(counts.size(), 300, "sanity: 300 generated nodes")
	# Floors at N=300: floor(300×0.10)=30, floor(30×0.17)=5, floor(5×0.30)=1,
	# floor(1×0.30)=0 (tier-4 is 0-or-1 at this scale — no floor to assert).
	_assert_floor(counts, 1, 30, "seed 12345 @300 (tier-1)")
	_assert_floor(counts, 2, 5, "seed 12345 @300 (tier-2)")
	_assert_floor(counts, 3, 1, "seed 12345 @300 (tier-3)")
	_assert_cap(counts, "seed 12345 @300")


func test_floors_hold_across_seeds() -> void:
	for seed in [7, 424242]:
		var result: Dictionary = await _generate(_build_config(300, seed))
		var counts := _loop_counts(result.get("nodes", []))
		var context := "seed %d @300" % seed
		_assert_floor(counts, 1, 30, context)
		_assert_floor(counts, 2, 5, context)
		_assert_floor(counts, 3, 1, context)
		_assert_cap(counts, context)


func test_scaled_floors_at_3000() -> void:
	var result: Dictionary = await _generate(_build_config(3000, 777))
	var counts := _loop_counts(result.get("nodes", []))
	assert_eq(counts.size(), 3000, "sanity: 3000 generated nodes")
	# Floors at N=3000: floor(3000×0.10)=300, floor(300×0.17)=51,
	# floor(51×0.30)=15, floor(15×0.30)=4.
	_assert_floor(counts, 1, 300, "seed 777 @3000 (tier-1)")
	_assert_floor(counts, 2, 51, "seed 777 @3000 (tier-2)")
	_assert_floor(counts, 3, 15, "seed 777 @3000 (tier-3)")
	_assert_floor(counts, 4, 4, "seed 777 @3000 (tier-4)")
	_assert_cap(counts, "seed 777 @3000")


func test_zero_tier1_rate_yields_no_self_loops() -> void:
	var cfg := _build_config(300, 999)
	cfg.self_loop_tier1_rate = 0.0
	var result: Dictionary = await _generate(cfg)
	var counts := _loop_counts(result.get("nodes", []))
	assert_eq(
		counts.filter(func(c): return c > 0).size(), 0,
		"tier1 rate 0 must disable self-loops entirely (escape hatch)")
