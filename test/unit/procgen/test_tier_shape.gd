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
