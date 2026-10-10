extends GutTest

## The procgen addon pass draws nodes uniformly WITH replacement: each draw
## puts one addon on the drawn node and a repeat draw stakes it, so a node's
## stake always equals its addon count. Swept over seeds and two graph sizes;
## asserts the density ratio and the per-node invariants, never a literal knob.

const _PRESET := "res://procgen/presets/first_level/first_level.tres"
const _SEEDS := [11, 2024, 90210]
const _SIZES := [80, 240]


## `content` / `addon_policy` / `topology` are ExtResources a `duplicate(true)`
## does not deep-copy — re-duplicate each one this test writes, or the cached
## preset leaks the override into every later test.
func _config(seed_value: int, node_count: int, k: float = -1.0) -> GraphProcgenConfig:
	var cfg: GraphProcgenConfig = (load(_PRESET) as GraphProcgenConfig).duplicate(true)
	cfg.seed = seed_value
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = node_count
	if k >= 0.0:
		cfg.content = cfg.content.duplicate(true)
		cfg.content.addon_policy = cfg.content.addon_policy.duplicate(true)
		cfg.content.addon_policy.addons_per_100_nodes = k
	return cfg


func _generate(cfg: GraphProcgenConfig) -> Graph:
	var graph: Graph = autofree(load("res://graph/graph.tscn").instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	await GraphProcgen.generate(cfg, graph)
	return graph


func test_density_and_per_node_invariants_across_seeds_and_sizes() -> void:
	var saw_repeat := false
	for size in _SIZES:
		for s in _SEEDS:
			var cfg := _config(s, size)
			var policy: AddonPolicy = cfg.content.addon_policy
			var graph := await _generate(cfg)
			var nodes := graph.get_skill_nodes()
			var total := 0
			for sn: SkillNode in nodes:
				var count := sn.get_addons().size()
				total += count
				if count > 1:
					saw_repeat = true
				assert_lte(count, int(sn.get_local_value(&"addon_slots")),
						"%s: addon count within its slots" % sn.name)
				assert_eq(sn.stake_level, maxi(1, count),
						"%s: stake == max(1, addon count)" % sn.name)
				assert_lte(count, policy.max_addons_per_node,
						"%s: within procgen's per-node limit" % sn.name)
			var target := roundi(float(nodes.size()) * policy.addons_per_100_nodes / 100.0)
			assert_eq(total, target, "seed %d, N=%d: total addons == k*N/100" % [s, nodes.size()])
	assert_true(saw_repeat, "the sweep saw at least one repeat-drawn (staked) node")


func test_zero_density_places_no_addons() -> void:
	var graph := await _generate(_config(_SEEDS[0], _SIZES[0], 0.0))
	for sn: SkillNode in graph.get_skill_nodes():
		assert_eq(sn.get_addons().size(), 0, "%s: k=0 places nothing" % sn.name)
		assert_eq(sn.stake_level, 1)
