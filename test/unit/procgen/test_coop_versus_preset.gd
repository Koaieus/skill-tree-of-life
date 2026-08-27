extends GutTest

## Pins the *shape* of the coop/versus budget gradient (#550): richest at the
## centre, poorest at the rim — the mirror image of `first_level.tres`, so
## "spawn on the rim and work inwards" is a real economic gradient.
##
## The floats in the preset are owner-tunable in the inspector, so nothing here
## asserts an exact value. What is pinned is monotonicity inward, the two
## endpoints staying inside their design bands, and — the one authored value
## that could silently regress without any ratio-based assertion noticing —
## `outer_radius = 0`, the opt-in that lets `_propagate_mask_radius` track the
## auto-scaled mask instead of a hardcoded radius.

const _PRESET_PATH := "res://procgen/presets/coop_versus/coop_versus.tres"
const _FIRST_LEVEL_PATH := "res://procgen/presets/first_level/first_level.tres"

## Enough nodes for ~35 per decile; the assertions are ratios, so the shape
## holds at any count that fills the buckets.
const _NODE_COUNT := 350
const _SEED := 1550
## Budget is a *rolled* range, so a single roll per node leaves enough variance
## for two adjacent decile means to cross. Averaging many rolls per node
## isolates the positional term, which is what this test is about.
const _ROLLS_PER_NODE := 25
const _DECILES := 10


func _fresh_config() -> GraphProcgenConfig:
	# `generate` mutates the config in place (mask `size_for`, the propagated
	# `outer_radius`) and `load` is cached — so every pass gets its own copy.
	var cfg: GraphProcgenConfig = (load(_PRESET_PATH) as GraphProcgenConfig).duplicate(true)
	# #349: topology is a top-level module .tres (ExtResource); duplicate(true)
	# does not cross that boundary, so re-duplicate before mutating (acceptance 4).
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = _NODE_COUNT
	cfg.seed = _SEED
	return cfg


func _generate(cfg: GraphProcgenConfig) -> Array:
	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	return result.get("nodes", [])


## Mean budget per node, averaged over `_ROLLS_PER_NODE` draws from one
## deterministically seeded stream. Parallel to `nodes`.
func _mean_budgets(cfg: GraphProcgenConfig, nodes: Array) -> Array[float]:
	var policy: BudgetPolicy = cfg.content.budget_policy
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var out: Array[float] = []
	for n in nodes:
		var arch: StringName = n.get_meta("archetype", &"")
		var tags: Array = n.get_meta("role_tags", [])
		var total := 0.0
		for _i in _ROLLS_PER_NODE:
			total += float(policy.compute_budget(arch, n.position, tags, rng))
		out.append(total / float(_ROLLS_PER_NODE))
	return out


## Decile k spans r in [sqrt(k/10)·R, sqrt((k+1)/10)·R), so each holds ~1/10 of
## an area-uniform sample. Returns the mean budget per decile.
func _decile_means(nodes: Array, budgets: Array[float], radius: float) -> Array[float]:
	var sums := PackedFloat64Array()
	var counts := PackedInt32Array()
	sums.resize(_DECILES)
	counts.resize(_DECILES)
	for i in nodes.size():
		var t: float = clampf(nodes[i].position.length() / radius, 0.0, 0.999999)
		var k: int = mini(_DECILES - 1, int(t * t * _DECILES))
		sums[k] += budgets[i]
		counts[k] += 1
	var means: Array[float] = []
	for k in _DECILES:
		assert_gt(counts[k], 0, "decile %d is empty — raise _NODE_COUNT" % k)
		means.append(sums[k] / maxf(1.0, float(counts[k])))
	return means


func _gradient_radius(cfg: GraphProcgenConfig) -> float:
	return (cfg.content.budget_policy.budget_field as RadialGradientField).outer_radius


func test_gradient_radius_tracks_the_auto_scaled_mask() -> void:
	# The preset authors `outer_radius = 0` on purpose: it is the opt-in that
	# makes GraphProcgen fill it from the resolved mask. `ShapeMask.auto_scale`
	# defaults true, so a hardcoded radius would saturate the gradient over the
	# outer rim. Every other assertion here divides by R and so would pass
	# unchanged if someone "fixed" the zero — this is the one that would not.
	var authored: GraphProcgenConfig = load(_PRESET_PATH)
	var field := authored.content.budget_policy.budget_field as RadialGradientField
	assert_not_null(field, "budget_field should be a RadialGradientField")
	assert_eq(authored.n_random_starters, 0,
		"contenders only — #551 places the starters")
	assert_eq(authored.content.weight_profiles.size(), 1,
		"archetype weights only; no RadialBandProfile (#552)")

	var cfg := _fresh_config()
	assert_eq((cfg.content.budget_policy.budget_field as RadialGradientField).outer_radius, 0.0,
		"the preset must author outer_radius = 0 (the mask-tracking opt-in)")
	await _generate(cfg)
	assert_gt(_gradient_radius(cfg), 0.0,
		"generate should have filled outer_radius from the auto-scaled mask")


func test_budget_is_monotonic_inward() -> void:
	var cfg := _fresh_config()
	var nodes := await _generate(cfg)
	var means := _decile_means(nodes, _mean_budgets(cfg, nodes), _gradient_radius(cfg))
	for k in range(1, _DECILES):
		# Decile means in the failure message: re-running an 800-node generate
		# to find out which pair crossed is the expensive way to diagnose this.
		assert_true(means[k] <= means[k - 1],
			"budget should not rise outward; decile %d (%.2f) > decile %d (%.2f). all: %s"
			% [k, means[k], k - 1, means[k - 1], str(means)])


func test_centre_affords_a_tier_four() -> void:
	# cost[T4] = 8 (procgen/pools/tier_ladder.gd). Computed expectation ~9.8.
	var cfg := _fresh_config()
	var nodes := await _generate(cfg)
	var means := _decile_means(nodes, _mean_budgets(cfg, nodes), _gradient_radius(cfg))
	assert_gte(means[0], 8.0,
		"innermost decile should afford a T4; got %.2f" % means[0])


func test_rim_is_lean() -> void:
	# The spawn rim: a starting budget, not a prize. Computed expectation ~1.8.
	var cfg := _fresh_config()
	var nodes := await _generate(cfg)
	var means := _decile_means(nodes, _mean_budgets(cfg, nodes), _gradient_radius(cfg))
	assert_lte(means[_DECILES - 1], 4.0,
		"outermost decile should stay lean; got %.2f" % means[_DECILES - 1])


func test_same_seed_gives_the_same_budgets() -> void:
	var cfg_a := _fresh_config()
	var nodes_a := await _generate(cfg_a)
	var budgets_a := _mean_budgets(cfg_a, nodes_a)

	var cfg_b := _fresh_config()
	var nodes_b := await _generate(cfg_b)
	var budgets_b := _mean_budgets(cfg_b, nodes_b)

	assert_eq(nodes_a.size(), nodes_b.size(), "same seed should place the same node count")
	assert_eq(budgets_a, budgets_b, "same seed should roll the same per-node budgets")


func test_single_player_gradient_is_untouched() -> void:
	# Deliberately the OPPOSITE gradient: first_level starts you at the centre
	# and puts the prizes on the rim, coop_versus starts you on the rim and puts
	# them at the centre. Both are intentional — this guard exists so nobody
	# "fixes" one to match the other. See #550 / #516.
	var single: GraphProcgenConfig = load(_FIRST_LEVEL_PATH)
	var field := single.content.budget_policy.budget_field as RadialGradientField
	assert_eq(field.inner_value, 1.0, "first_level's centre stays poor")
	assert_eq(field.outer_value, 4.0, "first_level's rim stays rich")
