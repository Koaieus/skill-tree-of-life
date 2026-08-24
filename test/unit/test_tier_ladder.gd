extends GutTest

## Pins the tier-value law (#552): the bigger chunk always wins, by exactly 1,
## at every tier. This is what makes `tier_bias_k` a power dial rather than a
## texture one — see stat_pool.gd's `tier_bias_k` docstring.
func test_doubled_lower_tier_value_is_one_less_than_next_tier() -> void:
	for t in range(TierLadder.MIN_TIER, TierLadder.MAX_TIER):
		assert_eq(
			2 * TierLadder.value(t), TierLadder.value(t + 1) - 1,
			"2 * V[%d] should be V[%d] - 1" % [t, t + 1]
		)
