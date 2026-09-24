extends GutTest

## TierShape (#1078): a pool's per-tier weight is `t^power × ratio^(t-1)` over
## the ABSOLUTE tier, decoupled from the cost ladder.

func _shape(power: float, ratio: float) -> TierShape:
	var s := TierShape.new()
	s.power = power
	s.ratio = ratio
	return s


func _assert_weights(s: TierShape, expected: Array, label: String) -> void:
	for i in expected.size():
		var t := i + 1
		assert_almost_eq(s.weight(t), float(expected[i]), 1e-9,
				"%s: weight(%d)" % [label, t])


func test_default_shape_is_the_doubling_ladder() -> void:
	_assert_weights(TierShape.new(), [1, 2, 4, 8], "default")


func test_linear_flat_and_hump_shapes() -> void:
	_assert_weights(_shape(1.0, 1.0), [1, 2, 3, 4], "linear")
	_assert_weights(_shape(0.0, 1.0), [1, 1, 1, 1], "flat")
	_assert_weights(_shape(2.0, 0.5), [1, 2, 2.25, 2], "hump")


## Equivalence with the deleted `cost^k` law: cost(t) = 2^(t-1), so
## cost^k = (2^k)^(t-1) — ratio 2^k at power 0 reproduces every old k.
func test_ratio_two_to_the_k_reproduces_cost_power_k() -> void:
	for k in [1.0, 0.5, 0.0, -1.0]:
		var s := _shape(0.0, pow(2.0, k))
		for t in range(TierLadder.MIN_TIER, TierLadder.MAX_TIER + 1):
			assert_almost_eq(s.weight(t), pow(float(TierLadder.cost(t)), k), 1e-9,
					"k=%s t=%d" % [k, t])


func test_new_pool_has_its_own_tier_shape() -> void:
	var a := StatPool.new()
	var b := StatPool.new()
	assert_not_null(a.tier_shape, "a fresh pool has a tier_shape")
	assert_not_null(b.tier_shape)
	assert_ne(a.tier_shape, b.tier_shape, "two pools must not share one TierShape")


func test_to_entries_weight_is_pool_weight_times_tier_weight() -> void:
	var p := StatPool.new()
	p.stat_id = &"strength"
	p.pool_weight = 0.7
	p.tier_shape = _shape(2.0, 0.5)
	var entries := p.to_entries(&"")
	assert_eq(entries.size(), 4)
	for i in entries.size():
		var e: ModifierPoolEntry = entries[i]
		var t := TierLadder.MIN_TIER + i
		assert_almost_eq(p.tier_weight(t), p.tier_shape.weight(t), 1e-12, "tier_weight(%d)" % t)
		assert_almost_eq(e.weight, 0.7 * p.tier_weight(t), 1e-12, "entry t%d weight" % t)


func test_preview_shows_each_offered_tiers_share() -> void:
	var p := StatPool.new()
	p.min_tier = 3
	p.max_tier = 4
	assert_eq(p.format_tier_preview(), "T3 33% · T4 67%")
	assert_eq(p.get(&"tier_preview"), p.format_tier_preview(), "exposed as an inspector property")


func test_null_shape_falls_back_to_default_and_warns() -> void:
	var p := StatPool.new()
	p.stat_id = &"strength"
	p.tier_shape = null
	assert_almost_eq(p.tier_weight(4), 8.0, 1e-12)
	assert_true(Array(p._get_configuration_warnings()).any(
			func(w: String) -> bool: return w.contains("tier_shape")))


## Migration pin: universal.tres's mobility pools carried `k = 0.5`; their
## ratio 2^0.5 must reproduce `cost^0.5`.
func test_universal_mobility_pools_keep_their_sqrt_cost_weights() -> void:
	var pack: StatPack = load("res://procgen/pools/universal.tres")
	var seen := 0
	for p in pack.pools:
		if p.stat_id in [&"movement_points", &"deallocation_points"]:
			seen += 1
			for t in range(p.min_tier, p.max_tier + 1):
				assert_almost_eq(p.tier_weight(t), pow(float(TierLadder.cost(t)), 0.5), 1e-9,
						"%s t%d" % [p.stat_id, t])
		else:
			assert_eq(p.tier_shape.ratio, 2.0, "%s keeps the default shape" % p.stat_id)
	assert_eq(seen, 2)
