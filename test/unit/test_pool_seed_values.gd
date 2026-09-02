extends GutTest

## The v4 tier ladder as a FORMULA contract (#321 D6, re-scoped by #719).
##
## Every test here builds its own [StatPool] in code and pins the resulting
## table as literals. Nothing in this file reads `procgen/pools/*.tres`, and
## that is the point: the owner tunes those between balance passes, so a test
## that pinned their `unit_value` asserted the tuner's numbers rather than the
## engine's behaviour and went red on every deliberate pass (#717). Literals on
## a hand-built pool can't drift with content, and — unlike a test that
## re-derives the recurrence from the pool's own fields — they cannot mirror a
## bug in [method StatPool._tier_magnitude_bounds] and silently assert nothing.
##
## The ladder (#321 D6): cost = [1,2,4,8], V = [1,3,7,15]. A tier's HIGH bound
## is `unit_value × V[t]` (or its `value_overrides` entry); its LOW bound
## follows `L(1) = M`, `L(t+1) = H(t) + M`, where M is `range_floor` and
## defaults to `unit_value`. Value rungs are indexed relative to `min_tier`;
## cost stays absolute.
##
## Where the other two halves of pool coverage live:
##   - **Do the shipped pools obey this formula?** — `test_pool_range_bounds.gd`
##     sweeps every pool in the specimen set for conformance against whatever
##     it authors. Tune-proof: the `.tres` is the input, never the expectation.
##   - **Did pool content change unintentionally?** — the procgen goldens
##     (`test/unit/procgen/test_preset_generation_golden.gd`). That is their
##     job, and they are the only layer that should go red on a tune.


## A bare pool with no archetype/tags — just the ladder fields under test.
func _pool(unit: float, op: int = StatModifier.Operation.ADD_BASE,
		min_t: int = 1, max_t: int = 4, floor_m: float = StatPool.FLOOR_UNSET) -> StatPool:
	var p := StatPool.new()
	p.stat_id = &"strength"
	p.operation = op
	p.unit_value = unit
	p.min_tier = min_t
	p.max_tier = max_t
	p.range_floor = floor_m
	return p


func _assert_table(entries: Array[ModifierPoolEntry], costs: Array, lows: Array, highs: Array,
		what: String) -> void:
	assert_eq(entries.size(), costs.size(), "%s: one entry per offered tier" % what)
	for i in mini(entries.size(), costs.size()):
		var e: ModifierPoolEntry = entries[i]
		assert_eq(e.cost, costs[i], "%s T%d cost" % [what, i + 1])
		assert_almost_eq(e.value_range.x, lows[i], 0.001, "%s T%d low" % [what, i + 1])
		assert_almost_eq(e.value_range.y, highs[i], 0.001, "%s T%d high" % [what, i + 1])


func test_addb_with_default_floor_flattens_to_the_seed_table() -> void:
	# The original #321 seed row (unit 2, no authored floor): T1..T4 resolve to
	# +2 +6 +14 +30 at costs 1 2 4 8. With M defaulting to `unit_value`, T1 is
	# a zero-width fixed point and T2..T4 gain real width off the recurrence.
	_assert_table(_pool(2.0).to_entries(),
			[1, 2, 4, 8], [2.0, 4.0, 8.0, 16.0], [2.0, 6.0, 14.0, 30.0],
			"addb unit 2, default M")


func test_an_authored_floor_widens_t1_and_shifts_the_low_chain() -> void:
	# What an authored `range_floor` buys, pinned as literals: M no longer
	# tracks `unit_value`, so T1 stops being a fixed point and every higher
	# tier's low drops to H(previous) + M. This is the shape the shipped
	# attribute pools took in `b3975d8` (unit 3, floor 1) — pinned HERE, on a
	# hand-built pool, precisely so re-tuning that `.tres` cannot turn it red.
	_assert_table(_pool(3.0, StatModifier.Operation.ADD_BASE, 1, 4, 1.0).to_entries(),
			[1, 2, 4, 8], [1.0, 4.0, 10.0, 22.0], [3.0, 9.0, 21.0, 45.0],
			"addb unit 3, M 1")


func test_overrides_pin_their_own_tier_and_still_feed_the_next_low() -> void:
	# #629: an override "pins a tier to an exact value, bypassing the roll
	# entirely" — so an overridden tier is a zero-width fixed point. Its
	# (overridden) H still feeds the NEXT tier's low through the chain. The
	# seed row that motivated the escape hatch is crit_chance .inc: unit 5,
	# overrides {3: 50, 4: 100} → +5 +15 +50 +100 at costs 1 2 4 8.
	var p := _pool(5.0, StatModifier.Operation.INCREASE)
	p.value_overrides = {3: 50.0, 4: 100.0}
	# T1 = M = 5 (zero-width, min_tier); T2 low = H(1) + M = 10; T3/T4 are
	# their own overrides at both ends.
	_assert_table(p.to_entries(),
			[1, 2, 4, 8], [5.0, 10.0, 50.0, 100.0], [5.0, 15.0, 50.0, 100.0],
			"inc unit 5 + overrides")


func test_max_tier_is_the_honest_brake() -> void:
	# `max_tier < 4` caps a flat ladder instead of hiding the brake in a
	# descending weight curve (#321 D6) — the shape the mobility pack uses:
	# unit 1, max_tier 2 → +1 +3 at costs 1 2, nothing above.
	_assert_table(_pool(1.0, StatModifier.Operation.ADD_BASE, 1, 2).to_entries(),
			[1, 2], [1.0, 2.0], [1.0, 3.0], "addb unit 1, max_tier 2")


func test_multiply_folds_the_plus_one_into_both_ends() -> void:
	# For MULTIPLY, `unit_value` is the "more" EXCESS and to_entries folds the
	# +1 into both bounds, so the ×1 base stays fixed. min_tier 3 also
	# exercises the relative-rung rule below: T3 is the pool's FIRST tier, so
	# it is V1 (×1) despite costing 4.
	_assert_table(_pool(0.05, StatModifier.Operation.MULTIPLY, 3, 4).to_entries(),
			[4, 8], [1.05, 1.10], [1.05, 1.15], "mul unit 0.05, min_tier 3")
	# …and with an authored floor (the shape `b3975d8` gave strength .mul),
	# T3 widens off its fixed point: M = 0.02 → ×1.02..×1.05, then
	# L(T4) = H(T3) + M = 0.05 + 0.02 → ×1.07.
	_assert_table(_pool(0.05, StatModifier.Operation.MULTIPLY, 3, 4, 0.02).to_entries(),
			[4, 8], [1.02, 1.07], [1.05, 1.15], "mul unit 0.05, M 0.02")


func test_a_negative_pool_orders_its_pair_by_role_not_by_sign() -> void:
	# #637: a negative pool rolls a real range like any other, and the pair is
	# ordered by ROLE — the ladder end (`unit × V[t]`, the far end) is `lo` and
	# the recurrence end (the near end) is `hi`, mirroring a positive pool.
	# unit -3, floor -1 → T1 -3..-1, T2 -9..-4, T3 -21..-10, all at POSITIVE
	# cost (refund economics retired). This is the shape the CON pack's INT
	# pool ships, pinned here so re-tuning it cannot turn this red.
	_assert_table(_pool(-3.0, StatModifier.Operation.INCREASE, 1, 3, -1.0).to_entries(),
			[1, 2, 4], [-3.0, -9.0, -21.0], [-1.0, -4.0, -10.0], "inc unit -3, M -1")


func test_min_tier_indexes_value_relative_to_first_tier() -> void:
	# The ladder rule: cost stays absolute, value rungs are indexed relative
	# to the pool's first tier. min_tier=3 → t3 costs 4 but is V1 (×1), t4
	# costs 8 and is V2 (×3). Default M makes t3 zero-width, t4 low = H(t3) + M.
	_assert_table(_pool(1.0, StatModifier.Operation.ADD_BASE, 3, 4).to_entries(),
			[4, 8], [1.0, 2.0], [1.0, 3.0], "addb unit 1, min_tier 3")


func test_every_flattened_entry_cost_is_legal() -> void:
	# #637 acceptance 3 — no unrollable content, and refund economics are
	# RETIRED (superseded 2026-08-30, see docs/domain/procgen-v4.md): every
	# flattened entry across ALL packs costs a legal, POSITIVE ladder rung
	# (1/2/4/8), whatever the sign of its rolled value. A negative-unit_value
	# pool used to cost the NEGATION of the rung (refunding budget instead of
	# spending it, settled 2026-08-07) — that mechanic is gone. Cost is `+T`
	# universally now; budget spend is monotonic (no draw ever increases
	# `remaining`).
	#
	# This is the one test here that still reads the shipped content, and it
	# stays tune-proof by construction: it asserts a PROPERTY of every entry
	# (its cost is a rung) rather than any particular pool's numbers.
	var legal_rungs: Array[int] = []
	for t in range(TierLadder.MIN_TIER, TierLadder.MAX_TIER + 1):
		legal_rungs.append(TierLadder.cost(t))

	var pool_set: ModifierPoolSet = preload("res://procgen/pools/specimen_pool_set.tres")
	var checked := 0
	var negative_pool_entries_seen := 0
	for pack in pool_set.packs:
		for sp in pack.pools:
			var p: StatPool = sp as StatPool
			var is_negative_pool := p.unit_value < 0.0
			for e in p.to_entries():
				checked += 1
				assert_true(legal_rungs.has(e.cost),
					"%s cost %d is not a ladder rung %s"
					% [String(p.stat_id), e.cost, str(legal_rungs)])
				assert_gt(e.cost, 0,
					"%s cost must be positive — refund economics retired (#637)" % String(p.stat_id))
				if is_negative_pool:
					negative_pool_entries_seen += 1
	assert_gt(checked, 20, "sweep should cover the whole specimen set")
	assert_gt(negative_pool_entries_seen, 0, "the specimen set still contains a negative unit_value pool at all")
