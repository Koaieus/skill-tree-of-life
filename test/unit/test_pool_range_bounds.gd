extends GutTest

## #628 — tunable minimum M (StatPool.range_floor) + computed tier bounds.
## Pins the two worked tables from the issue body exactly, the single
## validation rule (`range_floor <= unit_value`), the `value_overrides`
## inversion guard, the editor preview table, and the "no existing pool
## rebalances" regression across the whole specimen set. See
## docs/domain/procgen-v4.md and test_pool_seed_values.gd (which pins the
## seed-table pools' own H/L, unaffected by this file).

const _SET := preload("res://procgen/pools/specimen_pool_set.tres")


func _pool(unit_value: float, range_floor: float = StatPool.FLOOR_UNSET, min_tier: int = 1, max_tier: int = 4) -> StatPool:
	var p := StatPool.new()
	p.stat_id = &"strength"
	p.operation = StatModifier.Operation.ADD_BASE
	p.unit_value = unit_value
	p.range_floor = range_floor
	p.min_tier = min_tier
	p.max_tier = max_tier
	return p


## Acceptance 1: M=1.0, base 5.0 → T1 1..5, T2 6..15, T3 16..35, T4 36..75.
func test_worked_table_positive_m() -> void:
	var p := _pool(5.0, 1.0)
	var entries := p.to_entries()
	var expected := [
		Vector2(1.0, 5.0), Vector2(6.0, 15.0), Vector2(16.0, 35.0), Vector2(36.0, 75.0),
	]
	for i in entries.size():
		assert_almost_eq(entries[i].value_range.x, expected[i].x, 0.001, "T%d low" % (i + 1))
		assert_almost_eq(entries[i].value_range.y, expected[i].y, 0.001, "T%d high" % (i + 1))


## Acceptance 2: M=-10.0, base 5.0 → T1 -10..5, T2 -5..15, T3 5..35, T4 25..75.
func test_worked_table_negative_m() -> void:
	var p := _pool(5.0, -10.0)
	var entries := p.to_entries()
	var expected := [
		Vector2(-10.0, 5.0), Vector2(-5.0, 15.0), Vector2(5.0, 35.0), Vector2(25.0, 75.0),
	]
	for i in entries.size():
		assert_almost_eq(entries[i].value_range.x, expected[i].x, 0.001, "T%d low" % (i + 1))
		assert_almost_eq(entries[i].value_range.y, expected[i].y, 0.001, "T%d high" % (i + 1))


## Non-overlap is a CONSEQUENCE of a positive range_floor (L(t+1) - H(t) ==
## range_floor > 0), not a guaranteed property of the model — #628's body
## explicitly withdrew the sign-mismatch rejection an earlier revision used
## to protect it as an invariant. Assert it only where it structurally holds.
func test_non_overlap_holds_for_positive_m() -> void:
	var p := _pool(5.0, 1.0)
	var entries := p.to_entries()
	for i in range(entries.size() - 1):
		assert_true(entries[i + 1].value_range.x > entries[i].value_range.y,
				"T%d low should exceed T%d high under positive M" % [i + 2, i + 1])


## Acceptance 3: M > unit_value is rejected with a warning naming the pool;
## M negative (even deeply so) is accepted.
func test_floor_exceeding_unit_value_warns() -> void:
	var p := _pool(5.0, 6.0)
	var warnings := p._get_configuration_warnings()
	var named := false
	for w in warnings:
		if String(p.resource_name) in w and "range_floor" in w:
			named = true
	assert_true(named, "warning should name the pool and mention range_floor")


func _count_mentioning(warnings: PackedStringArray, needle: String) -> int:
	var n := 0
	for w in warnings:
		if needle in w:
			n += 1
	return n


func test_negative_floor_is_accepted() -> void:
	var p := _pool(5.0, -10.0)
	var warnings := p._get_configuration_warnings()
	assert_eq(_count_mentioning(warnings, "range_floor"), 0, "negative M must not warn: %s" % str(warnings))


func test_floor_equal_to_unit_value_is_accepted() -> void:
	# The boundary itself (M == unit_value) is valid, not just M < unit_value.
	var p := _pool(5.0, 5.0)
	var warnings := p._get_configuration_warnings()
	assert_eq(_count_mentioning(warnings, "range_floor"), 0, "M == unit_value must not warn: %s" % str(warnings))


## Acceptance 7: value_overrides is keyed on ABSOLUTE tier; the low-bound
## recurrence chains off the (possibly overridden) previous high. An override
## low enough to sit below its OWN tier's naturally-chained low must warn.
func test_value_override_inversion_warns() -> void:
	var p := _pool(5.0, 5.0, 1, 2)
	# Natural: T1 5..5, T2 low = H(1)+M = 10..15. Override T2's high to 1 —
	# below the chained low of 10 — inverting T2's range.
	p.value_overrides = {2: 1.0}
	var warnings := p._get_configuration_warnings()
	var found := false
	for w in warnings:
		if "T2" in w and "inverted" in w:
			found = true
	assert_true(found, "an override producing lo > hi must warn: %s" % str(warnings))


## Acceptance 4 + 5: default M (range_floor unset) reproduces the pre-#628
## high bound for EVERY authored pool (no rebalance) and passes validation
## with no range_floor complaint, across the whole specimen set.
func test_every_authored_pool_default_m_matches_old_highs_and_validates() -> void:
	var checked := 0
	for pack in _SET.packs:
		for sp in pack.pools:
			var p: StatPool = sp as StatPool
			assert_true(is_inf(p.range_floor), "%s should not author range_floor" % String(p.stat_id))
			var warnings := p._get_configuration_warnings()
			for w in warnings:
				assert_false("range_floor" in w or "inverted" in w,
						"%s should validate under default M: %s" % [String(p.stat_id), w])
			var lo := clampi(p.min_tier, TierLadder.MIN_TIER, TierLadder.MAX_TIER)
			var hi := clampi(p.max_tier, lo, TierLadder.MAX_TIER)
			var entries := p.to_entries()
			for i in entries.size():
				var t := lo + i
				var expected_h := float(p.value_overrides.get(t, p.unit_value * TierLadder.value(t - p.min_tier + 1)))
				if p.operation == StatModifier.Operation.MULTIPLY:
					expected_h = 1.0 + expected_h
				assert_almost_eq(entries[i].value_range.y, expected_h, 0.001,
						"%s T%d high must match the pre-#628 formula exactly" % [String(p.stat_id), t])
				checked += 1
	assert_gt(checked, 20, "sweep should cover the whole specimen set")


## Default M makes the pool's own first tier zero-width — the anchor every
## other test above assumes.
func test_default_m_zero_widths_first_tier() -> void:
	var p := _pool(5.0)
	var entries := p.to_entries()
	assert_almost_eq(entries[0].value_range.x, entries[0].value_range.y, 0.0001,
			"first tier is a fixed point under default M")


## Acceptance 6: the editor preview table shows L..H and a mean matching the
## computed bounds.
func test_format_table_shows_computed_bounds_and_mean() -> void:
	var p := _pool(5.0, 1.0)
	p.stat_id = &"strength"
	var table := p.format_table()
	assert_true("1.00..5.00" in table, "T1 range should print: %s" % table)
	assert_true("36.00..75.00" in table, "T4 range should print: %s" % table)
	# T2: low 6, high 15 → mean 10.5.
	assert_true("10.50" in table, "T2 mean should print: %s" % table)
